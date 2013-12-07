#!/usr/bin/env ruby
# encoding: utf-8

require_relative 'xiami_cloner'

XiamiCloner.clone(File.expand_path('~/Dropbox/Synced/Playlist'), File.expand_path('~/Music/Xiami Local'), cloned_file: File.expand_path('~/Music/Xiami Local/.Cloned'), import_to_itunes: false)
