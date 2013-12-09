# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xiami_cloner/version'

Gem::Specification.new do |spec|
  spec.name          = "xiami_cloner"
  spec.version       = XiamiCloner::VERSION
  spec.authors       = ["Jiahao Li"]
  spec.email         = ["isundaylee.reg@gmail.com"]
  spec.description   = %q{A gem for downloading music from Xiami. }
  spec.summary       = %q{A gem for downloading music from Xiami. }
  spec.homepage      = "http://github.com/isundaylee/xiami_cloner"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  spec.add_dependency "nokogiri"
  spec.add_dependency "ruby-pinyin"

  # brew install freeimage
  spec.add_dependency "image_science"

  # brew install taglib
  spec.add_dependency "taglib-ruby"
end
