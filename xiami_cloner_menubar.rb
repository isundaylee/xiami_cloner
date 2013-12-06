#!/usr/bin/env ruby
# encoding: utf-8

framework "Cocoa"
require 'thread'

class XiamiClonerMenubar

	# We build the status bar item menu
	def setup_menu
	  menu = NSMenu.new
	  menu.initWithTitle '虾米同步状态'

	  @log_menus = []

	  5.times { @log_menus << NSMenuItem.new }
	  @log_menus.each { |m| menu.addItem m }

	  mi = NSMenuItem.new
	  mi.title = '退出'
	  mi.action = 'quit:'
	  mi.target = self
	  menu.addItem mi

	  menu
	end

	# Init the status bar
	def init_status_bar(menu)
	  status_bar = NSStatusBar.systemStatusBar
	  status_item = status_bar.statusItemWithLength(NSVariableStatusItemLength)
	  status_item.setMenu menu 
	  status_item.setImage(NSImage.new.initWithContentsOfFile('icons/perok.png'))

	  @status_item = status_item
	end

	def quit(sender)
	  app = NSApplication.sharedApplication
	  app.terminate(self)
	end

	def initialize()
		app = NSApplication.sharedApplication
		init_status_bar(setup_menu)

		Thread.new do |t|
			while true
				logs_a = `tail -n 5 ~/Library/Logs/xiami_cloner.log`.split("\n").map { |x| x.split("\r").last }

				0.upto(4) { |i| @log_menus[i].title = logs_a[i] }

				last = logs_a[4]

				if last == '同步完成'
					@status_item.setImage(NSImage.new.initWithContentsOfFile('icons/perok.png'))
				elsif last == '开始同步'
					@status_item.setImage(NSImage.new.initWithContentsOfFile('icons/per00.png'))
				elsif /正在下载.*?/.match(last)
					@status_item.setImage(NSImage.new.initWithContentsOfFile('icons/per00.png'))
				elsif /#*?\w*?([0-9]*\.[0-9]*)%/.match(last)
					progress = /#*?\w*?([0-9]*\.[0-9]*)%/.match(last)[1].to_f
					i = (progress / 10).to_i
					s = i.to_s
					s = "0#{s}" if s.length == 1
					@status_item.setImage(NSImage.new.initWithContentsOfFile("icons/per#{s}.png"))
				end

				sleep 1
			end
		end

		app.run
	end

end

XiamiClonerMenubar.new