# encoding: utf-8

require_relative 'location_decoder.rb'

class XiamiCloner

	require 'fileutils'
	require 'digest/md5'
	require 'nokogiri'

	INFO_URL = 'http://www.xiami.com/song/playlist/id/%d/object_name/default/object_id/0'
	CACHE_DIR = '/tmp/xiami_cloner_cache'

	def self.clone(playlist, outdir, options = {})
		cloneds = options[:cloned_file] && File.exists?(options[:cloned_file])?
			strip_invalid(File.read(options[:cloned_file]).lines) :
			[]
		songs = strip_invalid(File.read(playlist).lines)

		counter = 0

		songs.each do |song|
			counter += 1

			print "正在下载第 #{counter} / #{songs.size} 首歌曲"

			if cloneds.include?(song)
				puts " ... 跳过"
				next
			end

			self.clone_song(song, outdir, options)

			cloneds << song
			File.write(options[:cloned_file], cloneds.join("\n")) if options[:cloned_file]

			puts
		end
	end

	private
		def self.retrieve_info(id)
			info_url = INFO_URL % id

			self.download_to_cache(info_url, "#{id}.info")

			Nokogiri::XML(File.read(self.cache_path("#{id}.info")))
		end

		def self.strip_invalid(list)
			list.select { |x| x.to_i > 0 }.map { |x| x.strip }
		end

		def self.clone_song(song, outdir, options = {})
			FileUtils.mkdir_p outdir

			info = retrieve_info(song)
			url = LocationDecoder.decode(info.search('location').text)

			self.download_to_cache(url, "#{song}.mp3", false)

			out_path = File.join(outdir, filename(song))
			out_path = uniquefy(out_path, ".mp3")

			FileUtils.cp(self.cache_path("#{song}.mp3"), out_path)

			write_id3(song, out_path)
		end

		def self.filename(song)
			info = retrieve_info(song)
			"#{info.search('artist').text} - #{info.search('title').text}"
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

		def self.download_to_cache(url, filename, hidden = true)
		    require 'fileutils'

		    FileUtils.mkdir_p(File.expand_path(CACHE_DIR))

		    ccp = File.join(File.expand_path(CACHE_DIR), filename + ".tmp")
		    cfp = File.join(File.expand_path(CACHE_DIR), filename)

		    if !File.exists?(cfp)
		    	FileUtils.rm_rf(ccp)
		    	command = "curl --retry 999 --retry-max-time 0 -C - -# \"#{url}\" -o \"#{ccp}\""
		    	command += " > /dev/null 2>&1" if hidden
		    	system(command)
		    	FileUtils.mv(ccp, cfp)
		    end
		end

		def self.write_id3(song, path)
			require 'taglib'

			info = retrieve_info(song)

			TagLib::MPEG::File.open(path) do |f|
				tag = f.id3v2_tag

				tag.artist = info.search('artist').text
				tag.album = info.search('album_name').text
				tag.title = info.search('title').text
				tag.genre = "Xiami"

				lyrics = simplify_lyrics(retrieve_lyrics(song))

				unless lyrics.strip.empty?
					tag.remove_frames('USLT')
					t = TagLib::ID3v2::UnsynchronizedLyricsFrame.new(TagLib::String::UTF8)
					t.text = lyrics
					tag.add_frame(t)
				end

				apic = TagLib::ID3v2::AttachedPictureFrame.new
				apic.mime_type = 'image/png'
				apic.description = 'Cover'
				apic.type = TagLib::ID3v2::AttachedPictureFrame::FrontCover
				apic.picture = retrieve_cover(song)

				tag.add_frame(apic)

				f.save
			end
		end

		def self.cache_path(filename)
			File.join(CACHE_DIR, filename)
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
				self.download_to_cache(info.search('pic').text, "#{song}.cover")
				return File.open(self.cache_path("#{song}.cover"), 'rb').read
			else
				return nil
			end
		end

end

XiamiCloner.clone('Playlist', 'songs', cloned_file: 'Cloned')