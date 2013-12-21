# encoding: utf-8

require "xiami_cloner/version"
require "xiami_cloner/location_decoder"

module XiamiCloner
	class Cloner

		require 'fileutils'
		require 'digest/md5'
		require 'nokogiri'
		require 'net/http'
		require 'ruby-pinyin'
		require 'image_science'
		require 'json'

		INFO_URL = 'http://www.xiami.com/song/playlist/id/%d/object_name/default/object_id/0'
		ALBUM_PAGE_URL = 'http://www.xiami.com/album/%d'
		GET_HQ_URL = 'http://www.xiami.com/song/gethqsong/sid/%d'
		CACHE_DIR = '~/Library/Caches/xiami_cloner'

		def self.clone(playlist, outdir, options = {})
			cloneds = options[:cloned_file] && File.exists?(options[:cloned_file])?
				strip_invalid(File.read(options[:cloned_file]).lines) :
				[]
			songs = strip_invalid(File.read(playlist).lines)
			terse = options[:terse]

			counter = 0

			songs.each do |song|
				counter += 1

				print "正在下载第 #{counter} / #{songs.size} 首歌曲" unless terse

				if cloneds.include?(song)
					puts " ... 跳过" unless terse
					next
				end

				puts

				self.clone_song(song, outdir, options)

				cloneds << song
				File.write(options[:cloned_file], cloneds.join("\n")) if options[:cloned_file]
			end
		end

		def self.clone_song(song, outdir, options = {})
			options[:import_to_itunes] ||= false
			terse = options[:terse]
			hq = options[:high_quality_song]
			cookie = options[:cookie]

			FileUtils.mkdir_p outdir

			print "正在下载 " unless terse

			info = retrieve_info(song)

			artist = info.search('artist').text
			title = info.search('title').text

			print "--- " if terse
			print "#{artist} - #{title} "
			puts

			url = retrieve_url(song, hq, cookie)

			if !url
				puts '  [信息] 无法下载歌曲'
				return
			end

			song_path = hq ? "#{song}.hq.mp3" : "#{song}.mp3"

			while true
				break if check_song_integrity(song, hq)
				FileUtils.rm(self.cache_path(song_path))
				self.download_to_cache(url, song_path, false)
			end

			out_path = File.join(outdir, filename(song))
			out_path = uniquefy(out_path, ".mp3")

			FileUtils.cp(self.cache_path(song_path), out_path)

			write_id3(song, out_path)

			if options[:import_to_itunes]
				import_to_itunes(out_path)
				puts "已将 #{artist} - #{title} 导入 iTunes" unless terse
			end
		end

		def self.check_integrity(playlist)
			songs = strip_invalid(File.read(playlist).lines)

			counter = 0

			songs.each do |song|
				counter += 1

				puts "正在检查第 #{counter} / #{songs.size} 首歌曲的完整性"

				puts "  歌曲 #{song} 没有下载完全" unless check_song_integrity(song)
			end
		end

		def self.retrieve_album_list(id)
			require 'open-uri'

			url = ALBUM_PAGE_URL % id

			doc = Nokogiri::HTML(open(url).read)

			doc.css('.song_name').map do |song|
				/\/song\/([0-9]*)/.match(song.css('a')[0]['href'])[1]
			end
		end

		private

			def self.retrieve_url(song, hq = false, cookie = nil)
				if hq
					download_to_cache(GET_HQ_URL % song, "#{song}.gethq", true, cookie)
					json = JSON.parse(File.open(cache_path("#{song}.gethq")) { |f| f.read })

					if json['status'].to_i == 1
						return nil if (!json['location'] || json['location'].empty?)
						url = LocationDecoder.decode(json['location'])
						if url =~ /auth_key/
							# It's the low quality version
							# Nasty hack
							# TODO FIXME
							puts "  [信息] 高清地址获取失败，使用低音质版本"
							return retrieve_url(song, false)
						else
							return url
						end
					else
						puts "  [信息] 无高音质版本可用，使用低音质版本"
						return retrieve_url(song, false)
					end
				else
					info = retrieve_info(song)
					return nil if (!info.search('location').text || info.search('location').text.empty?)
					return LocationDecoder.decode(info.search('location').text)
				end
			end

			def self.check_song_integrity(song, hq = false)
				path = hq ? "#{song}.hq.complete" : "#{song}.complete"

				return true if File.exists?(path)

				url = retrieve_url(song, hq)
				song_path = hq ? "#{song}.hq.mp3" : "#{song}.mp3"

				size = get_content_size(url)
				download_to_cache(url, song_path, false)

				if File.size(cache_path(song_path)) == size
					FileUtils.touch(cache_path(path))
					return true
				else
					return false
				end
			end

			def self.clear_cache(name)
				FileUtils.rm_f(cache_path(name))
			end

			def self.retrieve_info(id)
				info_url = INFO_URL % id
				info_path = "#{id}.info"

				if File.exists?(cache_path(info_path)) && (File.ctime(cache_path(info_path)) < (Time.now - 3600))
					# Remove if cached more than an hour ago
					FileUtils.rm(cache_path(info_path))
				end

				self.download_to_cache(info_url, info_path)

				Nokogiri::XML(File.read(self.cache_path(info_path)))
			end

			def self.retrieve_order(page, id)
				node = page.at_css('#track .chapter')

				node.css('.track_list').each_with_index do |d, i|
					disc = i + 1
					d.css('tr td.song_name a').each_with_index do |s, i|
						song = i + 1
						return [disc.to_s, song.to_s] if s['href'].include?(id.to_s)
					end
				end

				['', '']
			end

			def self.retrieve_publish_year(page)
				node = page.at_css('#album_block table')

				node.css('tr').each do |r|
					ds = r.css('td')
					if ds[0].text == '发行时间：'
						match = /([0-9]*)年/.match(ds[1].text)
						if match
							return match[1]
						else
							return ''
						end
					end
				end

				''
			end

			def self.retrieve_album_page(id)
				page_url = ALBUM_PAGE_URL % id
				page_path = "album_#{id}.page"

				self.download_to_cache(page_url, page_path)

				Nokogiri::HTML(File.read(self.cache_path(page_path)))
			end

			def self.strip_invalid(list)
				list.select { |x| x.to_i > 0 }.map { |x| x.strip }
			end

			def self.filename(song)
				info = retrieve_info(song)
				"#{info.search('artist').text} - #{info.search('title').text}"
			end

			def self.import_to_itunes(file)
			    itd = File.expand_path("~/Music/iTunes/iTunes Media/Automatically Add to iTunes.localized")

			    FileUtils.cp(file, itd)
			end

			def self.uniquefy(filename, extname)
				return filename + extname unless File.exists?(filename + extname)

				i = 2

				while true
					new_path = filename + " " + i.to_s + extname
					return new_path unless File.exists?(new_path)
					i += 1
				end
			end

			def self.download_to_cache(url, filename, hidden = true, cookie = nil)
			    require 'fileutils'
			    # hidden = false

			    FileUtils.mkdir_p(File.expand_path(CACHE_DIR))

			    ccp = File.join(File.expand_path(CACHE_DIR), filename + ".tmp")
			    cfp = File.join(File.expand_path(CACHE_DIR), filename)

			    if !File.exists?(cfp)
			    	FileUtils.rm_rf(ccp)
			    	command = "curl --connect-timeout 15 --retry 999 --retry-max-time 0 -C - -# \"#{url}\" -o \"#{ccp}\""
			    	# Changes User-Agent to avoid blocking HQ songs
			    	command += " --cookie #{cookie}" if cookie
			    	command += " > /dev/null 2>&1" if hidden
			    	system(command)

			    	if !File.exists?(ccp)
			    		# TODO FIXME
			    		# If curl goes to 404 or other errors, create stub file
			    		FileUtils.touch(cfp)
			    	else
				    	FileUtils.mv(ccp, cfp)
				    end
			    end
			end

			def self.retrieve_album_artist(page)
				page.css('table tr td a').each do |i|
					return i.text if /\/artist\/([0-9]*)/.match(i['href'])
				end
			end

			def self.get_text_frame(frame_id, text)
				t = TagLib::ID3v2::TextIdentificationFrame.new(frame_id, TagLib::String::UTF8)
				t.text = text.to_s
				t
			end

			def self.write_id3(song, path)
				require 'taglib'

				info = retrieve_info(song)

				TagLib::MPEG::File.open(path) do |f|
					tag = f.id3v2_tag

					# Basic infos
					tag.artist = info.search('artist').text
					tag.album = info.search('album_name').text
					tag.title = info.search('title').text
					tag.genre = "Xiami"

					# Album artist
					album_page = retrieve_album_page(info.search('album_id').text.to_i)
					album_artist = retrieve_album_artist(album_page)
					tag.remove_frames('TPE2')
					tag.add_frame(get_text_frame('TPE2', album_artist))

					# Sorting fields
					tag.remove_frames('TSOT')
					tag.add_frame(get_text_frame('TSOT', PinYin.sentence(tag.title)))

					tag.remove_frames('TSOA')
					tag.add_frame(get_text_frame('TSOA', PinYin.sentence(tag.album)))

					tag.remove_frames('TSOP')
					tag.add_frame(get_text_frame('TSOP', PinYin.sentence(tag.artist)))

					tag.remove_frames('TSO2')
					tag.add_frame(get_text_frame('TSO2', PinYin.sentence(album_artist)))

					# Track order (returns strings that are empty if not retrieved successfully)
					disc, track = retrieve_order(album_page, song)

					tag.remove_frames('TRCK')
					tag.add_frame(get_text_frame('TRCK', track))

					tag.remove_frames('TPOS')
					tag.add_frame(get_text_frame('TPOS', disc))

					# Track year (returns string that is empty if not retrieved successfully)
					year = retrieve_publish_year(album_page)

					tag.remove_frames('TDRC')
					tag.add_frame(get_text_frame('TDRC', year))

					# Lyrics
					lyrics = simplify_lyrics(retrieve_lyrics(song))
					unless lyrics.strip.empty?
						tag.remove_frames('USLT')
						t = TagLib::ID3v2::UnsynchronizedLyricsFrame.new(TagLib::String::UTF8)
						t.text = lyrics
						tag.add_frame(t)
					end

					# Album cover
					apic = TagLib::ID3v2::AttachedPictureFrame.new
					apic.mime_type = 'image/png'
					apic.description = 'Cover'
					apic.type = TagLib::ID3v2::AttachedPictureFrame::FrontCover
					apic.picture = retrieve_cover(song)
					tag.add_frame(apic)

					# Save
					f.save
				end
			end

			def self.cache_path(filename)
				File.expand_path(File.join(CACHE_DIR, filename))
			end

			def self.simplify_lyrics(l)
	    		ls = l.lines.to_a
			    nls = []

			    ls.each do |ll|
			    	unless ll =~ /\[[^0-9][^0-9]:.*?\]/
				        ll.gsub! /\[.*?\]/, ''
				        nls += [ll.strip]
			    	end
			    end

			    nls.join("\n")
			end

			def self.retrieve_lyrics(song)
				info = retrieve_info(song)

				if info.search('lyric') && !info.search('lyric').text.strip.empty?
					self.download_to_cache(info.search('lyric').text, "#{song}.lrc")
					return File.read(self.cache_path("#{song}.lrc"))
				else
					return ''
				end
			end

			def self.retrieve_cover(song)
				info = retrieve_info(song)

				if info.search('pic') && !info.search('pic').text.strip.empty?
					url = info.search('pic').text

					re = /(\/[0-9]*)(_[0-9])(\.)/

					if !re.match(url)
						# Fallback low-res
						self.download_to_cache(url, "#{song}.cover")
						return File.open(self.cache_path("#{song}.cover"), 'rb').read
						puts "  [信息] 使用低清版本专辑封面"
					else
						# Retrieve and crop the high-res version
						new_url = url.gsub(re, '\1\3')

						return File.open(self.cache_path("#{song}.cover_hq_c"), 'rb').read if File.exists?(self.cache_path("#{song}.cover_hq_c"))

						self.download_to_cache(new_url, "#{song}.cover_hq")
						ImageScience.with_image(cache_path("#{song}.cover_hq")) do |img|
							img.cropped_thumbnail(500) do |thumb|
								thumb.save cache_path("#{song}.cover_hq_c")
							end
						end

						return File.open(self.cache_path("#{song}.cover_hq_c"), 'rb').read
					end
				else
					return nil
				end
			end

			def self.get_content_size(url)
				response = `curl -s -I \"#{url}\"`

				regexp = /Content-Length: ([0-9]*)[^0-9]/

				regexp.match(response)[1].to_i
			end

	end
end