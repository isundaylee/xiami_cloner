#!/usr/bin/env ruby
# encoding: utf-8

require_relative 'xiami_cloner'

require 'fileutils'

`lock_acquire xiami_cloner`

exit unless `lock_check xiami_cloner`.strip == 'true'

trigger_file = '/tmp/xiami_cloner.trigger'
lock_file = '/tmp/xiami_cloner.lock'

while true

	File.open(lock_file, 'w') do |lock|

		FileUtils.rm_f(trigger_file)

		unless lock.flock(File::LOCK_NB | File::LOCK_EX)
			puts "已有同步进程执行中"
			FileUtils.touch(trigger_file)
			exit
		end

		puts "开始同步"

		XiamiCloner.clone(File.expand_path('~/Dropbox/Synced/Playlist'), File.expand_path('~/Music/Xiami'), cloned_file: File.expand_path('~/Dropbox/Synced/Cloned'), import_to_itunes: true)

		puts "同步完成"

	end

	break unless File.exists?(trigger_file)

end

`lock_release xiami_sync`
