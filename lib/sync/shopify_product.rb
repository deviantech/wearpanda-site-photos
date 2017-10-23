module Sync
  class ShopifyProduct

    attr_accessor :product_id, :local_images
    def initialize(product_id:, local_images:)
      @product_id = product_id
      @local_images = local_images
    end

    def call
      to_add = if remote_image_hashes.nil? || remote_image_hashes.keys.count == 0
        App.log.info "No remote metafield mapping found -- #{App.dry? ? 'would clear' : 'clearing'} all existing images for #{product.title}".yellow
        product.images.map(&:destroy) unless App.dry?

        local_images
      else
        if (hashes_to_remove = remote_image_hashes.keys - local_image_hashes.keys).length > 0
          filenames_to_remove = remote_image_hashes.values_at( *hashes_to_remove )
          images_to_remove = product.images.select {|i| filenames_to_remove.include?( remote_image_filename(i.src) ) }
          App.log.info "[#{product.title}] #{App.dry? ? 'Would remove' : 'Removing'} #{images_to_remove.length} images: [#{images_to_remove.map {|i| remote_image_filename(i.src)}}]" if images_to_remove.length > 0
          images_to_remove.map(&:destroy) unless App.dry?
        end

        if (needed_hashes = local_image_hashes.keys - remote_image_hashes.keys).length > 0
          needed_files = local_image_hashes.values_at( *needed_hashes )
          App.log.info "[#{product.title}] #{App.dry? ? 'Would add' : 'Adding'} #{needed_files.length} new images"
          needed_files
        else []
        end
      end

      failures = to_add.map do |img|
        ShopifyProductImage.new(product, img)
      end.select do |img|
        if App.dry?
          App.log.info "\tWould upload: #{img.filename}".green
        else
          App.log.info "\tUploading: #{img.filename}".green
          !img.upload
        end
      end

      return if App.dry?

      raise "Failed to save all images. Failed: #{failures.map(&:filename)}.".red unless failures.blank?
      sync_remote_image_hashes
    rescue StandardError => e
      puts "\n\nWARNING: Error interrupted syncing, check product #{product_id} to be sure images weren't left in inconsistent state:\nhttps://#{ENV['SHOPIFY_SHOP']}.myshopify.com/admin/products/#{product_id}\n\n".red
      binding.pry
      raise e
    end

    private

    def remote_image_filename(src)
      src.split('/')[-1].split('?')[0]
    end

    def remote_image_filenames
      product.images.map {|i| remote_image_filename(i.src) }
    end

    def sync_remote_image_hashes
      if remote_image_hashes_metafield
        unless remote_image_hashes_metafield.value == JSON.dump(local_image_hashes)
          remote_image_hashes_metafield.value = JSON.dump(local_image_hashes)
          remote_image_hashes_metafield.save
          App.log.info "\tUpdated image hashes metafield to reflect new files"
        end
      else
        product.add_metafield(
          ShopifyAPI::Metafield.new({
            namespace: "panda",
            key: "image_hashes",
            value: JSON.dump(local_image_hashes),
            value_type: "string"
          })
        )
        App.log.info "\tCreated new metafield to store image hashes"
      end
    end

    def remote_image_hashes_metafield
      product.metafields.detect {|m| m.namespace == 'panda' && m.key == 'image_hashes'}
    end

    def remote_image_hashes
      return @remote_image_hashes if defined?(@remote_image_hashes)

      @remote_image_hashes = begin
        if raw = remote_image_hashes_metafield
          hashes = JSON.parse(raw.value)
          # If the remote metafield doesn't match the actual images uploaded, ignore it entirely
          hashes.values.sort == remote_image_filenames.sort ? hashes : nil
        end
      end
    end

    def local_image_hashes
      @local_image_hashes ||= local_images.each_with_object({}) do |img, hash|
        hash[ file_hash(img) ] = img
      end.tap do |hashes|
        App.warn(product.title, "appears to have duplicate local images") if hashes.keys.count < local_images.count
      end
    end

    def file_hash(img)
      Digest::MD5.hexdigest( ::File.read(img) )
    end

    def product
      @product ||= ShopifyAPI::Product.find(product_id)
    end

  end
end