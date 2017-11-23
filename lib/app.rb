require 'rubygems'
require 'bundler'

Bundler.setup
Bundler.require(:default)

require_relative 'traversal'

require_relative 'photos/base'
require_relative 'photos/editorial'
require_relative 'photos/square_editorial'
require_relative 'photos/header'
require_relative 'photos/product'

require_relative 'sync/shopify'
require_relative 'sync/shopify_product'
require_relative 'sync/shopify_product_image'

require_relative 'mirror/shopify'
require_relative 'mirror/structure'
require_relative 'mirror/product_info'

require 'logger'


# A couple helper methods
class Object
  def blank?
    self.nil? || self.to_s.nil? || self.to_s == ''
  end

  def present?
    !blank?
  end
end


# Usage: separate steps b/c otherwise dry run for publish can't tell what correct IDXes will be after renaming.

class InvalidStructure < StandardError; end

module App
  DRY = ENV['DRY'] || false
  QUIET = ENV['QUIET'] || false
  REPROCESS_ALL_FILES = ENV['REPROCESS_ALL_FILES'] || false
  UPTO_REGEX = /---upto(\d+)/

  class << self

    def log
      @log ||= Logger.new($stdout).tap do |l|
        l.progname = 'Photos'
        l.formatter = proc do |severity, time, progname, msg|
          color = case severity
          when 'DEBUG' then :light_black
          when 'INFO' then :cyan
          when 'WARN' then :yellow
          else :red
          end

          "#{progname}: #{msg}\n".send(color)
        end

      end
    end

    def root_dir
      File.expand_path( "#{File.dirname(__FILE__)}/.." )
    end

    def photos_dir
      File.join(root_dir, "photos")
    end

    def reprocess_all_files?
      REPROCESS_ALL_FILES
    end

    def dry?
      @force_dry || DRY
    end

    def force_dry!
      @force_dry = true
    end

    def force_wet!
      @force_dry = nil
    end

    def quiet?
      QUIET
    end

    # Debug in DRY, raise in production
    def warn(thing, msg=nil, error: nil, structural: true)
      message = "[#{thing}] ".cyan
      message += msg.present? ? msg.yellow : (error.present? ? error.message.red : raise("Invalid warning"))
      errors << message

      if dry?
        log.warn message
      elsif error
        log.fatal message
        raise error
      else
        raise (structural ? InvalidStructure : RuntimeError), message
      end
    end

    def action
      @@action
    end

    def block
      @@block
    end

    def rename(path)
      call_with_action(path, :rename)
    end

    def prepare(path)
      call_with_action(path, :prepare)
    end

    def publish(path)
      @api = Sync::Shopify.new(path)
      call_with_action(path, :publish)
    end



    def call_with_block(path, &block)
      @@action = :block
      @@block = block
      Traversal.call(path)
      success?
    end

    def call_with_action(path, action)
      @@action = action
      Traversal.call(path)
      success?
    end

    def errors
      @errors ||= []
    end

    def success?
      errors.blank?
    end

    def sync_api
      @api || raise("must call #publish before trying to access sync_api")
    end

    def dipping_into(dir)
      raise(InvalidStructure, "Expected directory, got file: #{view dir}") unless ::File.directory?(dir)

      cwd = FileUtils.pwd
      begin
        FileUtils.chdir(dir)
        yield
      ensure
        FileUtils.chdir(cwd)
      end
    end

    def image_hashes_for(local_images, product_name: nil)
      local_images.each_with_object({}) do |img, hash|
        hash[ img ] = file_hash(img)
      end.tap do |all_hashes|
        # Little complex to allow duplicate hashes as long as they're in different categories (e.g. reusing product image as editorial)
        hashes_by_type = all_hashes.group_by {|k,v| k.match(/(editorial|header)/)&.send(:[], 0) || 'product' }
        images_by_type = local_images.group_by {|k| k.match(/(editorial|header)/)&.send(:[], 0) || 'product' }

        hashes_by_type.each do |type, hashes|
          imgs = images_by_type[type]
          App.warn(product_name, "appears to have duplicate #{type} images") if hashes.uniq.count < imgs.count
        end
      end
    end

    def file_hash(img)
      Digest::MD5.hexdigest( ::File.read(img) )
    end

  end
end

Dotenv.load( "#{App.root_dir}/.env" )