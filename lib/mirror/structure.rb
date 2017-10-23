module Mirror
  class Structure
    attr_reader :info, :root
    def initialize(info)
      @info = info
      @root = Hash.new { |hash, key| hash[key] =  {} }

      build
    end

    private

    def build
      info.each do |p|
        root[p.category_name][p.product_name] ||= {
          '_editorials' => p.images_for_editorial,
          '_headers' => p.images_for_header,
          'product' => p.images_for_product,
        }

        p.skus.each do |sku|
          root[p.category_name][p.product_name][transformed_sku(sku)] = p.images_for_sku(transformed_sku(sku))
        end
      end
    end


    def transformed_sku(sku)
      sku.sub(/-(s|l)$/i, '')
    end

  end
end