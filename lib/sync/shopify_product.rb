module Sync
  class ShopifyProduct
    GUID_REGEX = /_\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\./

    attr_accessor :product_id, :local_images
    def initialize(product_id:, local_images:)
      @product_id = product_id
      @local_images = local_images
    end

    def call
      remove_unneeded_remotes
      upload_missing_images

      have = remote_image_filenames(force: true).map {|src| without_guid(src) }.sort
      wanted = local_image_hashes.keys.sort

      unless have == wanted
        extras = (have - wanted).any? ? "\n\tExtra: #{have - wanted}" : ''
        missing = (wanted - have).any? ? "\n\tMissing: #{wanted-have}" : ''
        App.log.fatal "[#{product.title}] Failed to properly sync images:#{extras}#{missing}\n\n"
      end
    rescue StandardError => e
      puts "\n\nWARNING: Error interrupted syncing, check product #{product_id} to be sure images weren't left in inconsistent state:\nhttps://#{ENV['SHOPIFY_SHOP']}.myshopify.com/admin/products/#{product_id}\n\n".red
      binding.pry
      raise e
    rescue
      puts "\n\nWARNING: Error interrupted syncing, check product #{product_id} to be sure images weren't left in inconsistent state:\nhttps://#{ENV['SHOPIFY_SHOP']}.myshopify.com/admin/products/#{product_id}\n\n".red
    end

    private

    def remove_unneeded_remotes
      return if App.dry?

      images_to_remove.each do |img|
        img.destroy rescue ActiveResource::ResourceNotFound
      end
    end

    def upload_missing_images
      return if images_to_add.blank?

      if App.dry?
        images_to_add.each {|img| App.log.info "\tWould upload: #{img}".green }
        return
      end

      App.log.info "\tUploading image(s) in parallel (#{images_to_add.length})"
      images_to_add {|i| App.log.debug "\t\t- #{i}" }

      failures = Parallel.map(images_to_add, progress: App.quiet? ? nil : "\tUploading", in_threads: 10) do |img|
        ShopifyProductImage.new(product, img).upload
      end.select {|img| !img.uploaded? }

      raise "Failed to save all images. Failed: #{failures.map(&:filename)}.".red unless failures.blank?
      sync_remote_image_hashes
    end

    def images_to_remove
      if ENV['FORCE_SYNC_ALL_IMAGES'] == '1' || remote_image_hashes.blank?
        App.log.info "[#{product.title}] #{App.dry? ? 'would clear' : 'clearing'} all existing images"
        product.images
      else
        removable_names = remote_image_hashes.select do |remote_name, remote_hash|
          local_image_hashes[ without_guid(remote_name) ] != remote_hash
        end.keys

        # Shopify has been randomly appending GUIDs unnecessarily. If any have GUIDs, check if they ALSO have a non-GUID version.
        # If so, remove the duplicate (w/ GUID) -- otherwise, we just ignore the GUID as best we can
        removable_names += remote_image_hashes.select do |remote_name, remote_hash|
          remote_name =~ GUID_REGEX && remote_image_hashes.detect {|rn, _| rn == without_guid(remote_name) }
        end.keys

        App.log.warn "[#{product.title}] #{App.dry? ? 'Would remove' : 'Removing'} #{removable_names.length} images: #{removable_names}" if removable_names.length > 0

        product.images.select {|i| removable_names.include?( remote_image_filename(i.src) ) }
      end
    end

    def images_to_add
      @images_to_add ||= begin
        product(force: true)

        if remote_image_hashes.blank?
          local_images
        else
          current_remotes_without_guids = remote_image_hashes.transform_keys {|k| without_guid(k) }
          to_add = local_image_hashes.select do |local_name, local_hash|
            current_remotes_without_guids[local_name] != local_hash
          end.keys
        end
      end
    end



    def remote_image_filename(src)
      src.split('/')[-1].split('?')[0]
    end

    # Note - automatically deletes any duplicated-by-filename images (shopify auto-appends a GUID)
    def remote_image_filenames(force: false)
      return @remote_image_filenames if defined?(@remote_image_filenames) && !force
      @product = ShopifyAPI::Product.find(product_id) if force

      @remote_image_filenames = product.images.map {|i| remote_image_filename(i.src) }
    end

    def sync_remote_image_hashes
      removed = if remote_image_hashes_metafield
        return if remote_image_hashes_metafield.value == JSON.dump(local_image_hashes)
        remote_image_hashes_metafield.destroy
      end

      product.add_metafield(
        ShopifyAPI::Metafield.new({
          namespace: "panda",
          key: "image_hashes",
          value: JSON.dump(local_image_hashes),
          value_type: "string"
        })
      )

      App.log.info "\t[#{product.title}] #{removed ? 'Updated image hashes metafield to reflect new files' : 'Created new metafield to store image hashes'}"
    end

    def remote_image_hashes_metafield
      product.metafields.detect {|m| m.namespace == 'panda' && m.key == 'image_hashes'}
    end

    def remote_image_hashes
      return @remote_image_hashes if defined?(@remote_image_hashes)

      @remote_image_hashes = begin
        if raw = remote_image_hashes_metafield
          JSON.parse(raw.value).tap do |hashes|
            # If the remote metafield doesn't match the actual images uploaded, ignore it entirely
            if hashes.keys.sort != remote_image_filenames.map {|src| without_guid(src) }.sort
              App.log.warn "[#{product.title}] Remote hashes metafield is out of sync with uploaded products - ignoring"
              return {}
            end
          end
        else
          App.log.info "[#{product.title}] No remote hashes metafield found"
          {}
        end
      end
    end

    def local_image_hashes
      @local_image_hashes ||= App.image_hashes_for(local_images, product_name: product.title)
    end

    def product(force: false)
      return @product if defined?(@product) && !force
      @product = ShopifyAPI::Product.find(product_id)
    end

    def without_guid(raw)
      raw.sub(GUID_REGEX, '.')
    end

  end
end