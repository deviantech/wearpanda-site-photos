module Sync
  class ShopifyProductImage

    attr_accessor :product, :filename, :sku, :num_for_sku
    def initialize(product, filename)
      @product = product
      @filename = filename

      matched = filename.match(/_?__(.+?)___?(\d+)?/) || []
      @sku = matched[1]
      @num_for_sku = matched[2].to_i

      @uploaded = nil
    end

    def upload
      img = ShopifyAPI::Image.new(attrs)
      img.attach_image( File.read(filename) )
      img.prefix_options = {
        product_id: product.id
      }

      if @uploaded = img.save
        maybe_update_primary_variant_image(img)
      end

      self
    end

    def uploaded?
      !! @uploaded
    end

    private

    def attrs
      {
        variant_ids: variant_ids,
        position: position,
        alt: alt_text,
      }.delete_if {|k,v| v.blank? }.merge({
        filename: filename,
      })
    end

    def maybe_update_primary_variant_image(img)
      return unless num_for_sku == 1

      variants.each do |v|
        v.image_id = img.id
        v.save
      end
    end

    def variant_ids
      variants.map(&:id)
    end

    def variants
      sku ? product.variants.select {|v| v.sku == sku } : []
    end

    def position # The first product image is at position 1 and is the "main" image for the product.
      return 1 if filename =~ /editorial/ && filename =~ /1/
    end

    def alt_text
      alt = exif.imagedescription.to_s
      return alt if alt.length > 0 && alt != 'Or the DESC field...'

      parts = [alt_prefix, product.title]

      show_sku_title = product.product_type != 'Watch'

      parts += if sku
         [show_sku_title ? variants.first&.title : nil, 'product image']
      elsif filename =~ /editorial/
        ['editorial image']
      else
        ['image']
      end

      parts.compact.join(' ')
    end

    def alt_prefix
      case product.product_type
      when 'Watch' then "Wooden Watch made from Bamboo and Sustainable Materials -"
      when /Sunglasses/ then "Eco-Friendly Bamboo #{product.product_type} -"
      end
    end

    def exif
      @exif ||= MiniExiftool.new(filename)
    end

  end
end