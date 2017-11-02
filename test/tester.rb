#!/usr/bin/env ruby
require_relative '../lib/app'


Mirror::Shopify.new('/Users/kali/code/wearpanda/site-photos/test-photos').call(overwrite: true)
# path = '../test-photos'
# App.rename(path)
# App.prepare(path)

#
# App.publish("../test-photos")