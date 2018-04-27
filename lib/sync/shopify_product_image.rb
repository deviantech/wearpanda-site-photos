module Sync
  class ShopifyProductImage

    attr_accessor :product, :filename
    def initialize(product, filename)
      @product = product
      @filename = filename
      @uploaded = nil
    end

    def upload
      img = ShopifyAPI::Image.new(attrs)
      img.attach_image( File.read(filename) )
      img.prefix_options = {
        product_id: product.id
      }

      @uploaded = img.save

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

    def variant_ids
      return unless sku
      product.variants.select {|v| v.sku == sku }.map(&:id)
    end

    def sku
      if matched = filename.match(/__(.+?)__/)
        matched[1]
      end
    end

    def position       # The first product image is at position 1 and is the "main" image for the product.
      return 1 if filename =~ /editorial/ && filename =~ /1/
    end

    def alt_text
      alt = exif.imagedescription.to_s
      return alt if alt.length > 0

      nil
    end

    def exif
      @exif ||= MiniExiftool.new(filename)
    end

  end
end