module Sync
  class Shopify

    attr_accessor :root_path, :structure
    def initialize(root_path)
      @root_path = root_path
      @structure = {}
      prep_api
    end

    def sync_product_up(dir)
      App.dipping_into('_live') do
        Sync::ShopifyProduct.new(product_id: dir.product_id, local_images: dir.send(:entries)).call
      end
    end

    private

    def prep_api
      ShopifyAPI::Base.site = "https://#{ENV.fetch('SHOPIFY_KEY')}:#{ENV.fetch('SHOPIFY_TOKEN')}@#{ENV.fetch('SHOPIFY_SHOP')}.myshopify.com/admin"
    end

  end
end