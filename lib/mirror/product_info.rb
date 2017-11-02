module Mirror
  class ProductInfo
    UNWANTED_PRODUCT_PARTS = %w(the)

    attr_reader :raw, :skus, :sku_images
    def initialize(raw)
      @raw = raw
      @skus = raw.variants.map(&:sku)
      @sku_images = raw.variants.each_with_object({}) {|v, hash| hash[v.sku] = v.image_id}
    end

    def category_name
      name = raw.vendor.downcase.sub(/panda/, '').gsub(/\W/, '').strip
      name = 'panda' if name.length == 0

      case name
      when 'locoporvino' then 'watches'
      when 'christmasshop' then 'xmas-shop'
      else name
      end
    end

    def product_name
      product = raw.title.downcase
      UNWANTED_PRODUCT_PARTS.each do |part|
        product.gsub!(/#{part}/, '')
      end

      "#{product.strip} - #{raw.id}"
    end

    def images_for_editorial
      processed_images[:editorial]
    end

    def images_for_header
      processed_images[:header]
    end

    def images_for_product
      processed_images[:product]
    end

    def images_for_sku(sku)
      processed_images[:sku][sku]
    end

    private

    def processed_images
      @processed_images ||= begin
        initial = {editorial: [], header: [], product: [], sku: Hash.new { |hash, key| hash[key] = [] }}
        raw.images.each_with_object(initial) do |img, hash|
          case img.src
          when /[^_]__(.+?)__[^_]/ then hash[:sku][$1] << img
          when /header/ then hash[:header] << img
          when /editorial/ then hash[:editorial] << img
          else
            hash[:product] << img
          end
        end
      end
    end

  end
end