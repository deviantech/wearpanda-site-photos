module Mirror
  class Shopify

    attr_accessor :root_path, :structure, :hydra, :bar, :requests
    def initialize(root_path)
      @root_path = root_path
      prep_api

      @hydra = Typhoeus::Hydra.new(max_concurrency: 25)
      @requests = 0
    end

    def call(overwrite: false)
      @structure = Mirror::Structure.new( remote_products )

      if ::File.exists?(root_path)
        overwrite ? FileUtils.rm_rf(root_path) : raise("root path already exists: #{root_path}")
      end

      FileUtils.mkdir_p(root_path)
      FileUtils.chdir(root_path)

      sync_structure

      puts "Processing #{requests} requests".cyan
      @bar = ProgressBar.create(format: '%a |%b>>%i| %p%% %t', total: requests)

      hydra.run
    end

    private

    def prep_api
      ShopifyAPI::Base.site = "https://#{ENV.fetch('SHOPIFY_KEY')}:#{ENV.fetch('SHOPIFY_TOKEN')}@#{ENV.fetch('SHOPIFY_SHOP')}.myshopify.com/admin"
    end

    def remote_products
      raw_products = ShopifyAPI::Product.find(:all, params: {page: 1, limit: 250}).tap do |p|
        raise("We have enough products that we need to implement pagination!".red) if p.length == 250
      end

      raw_products.map do |raw|
        next if raw.vendor.downcase == 'lensabl'
        next if raw.vendor.downcase =~ /materials/
        Mirror::ProductInfo.new(raw)
      end.compact
    end

    def sync_structure
      structure.root.each do |category, products|
        products.each do |product, product_dirs|
          product_dirs.each do |dir, images|
            dir_path = [category, product, dir].join('/')
            FileUtils.mkdir_p( dir_path )

            images.sort_by {|i| i.src }.each_with_index do |img|
              # They were live, so all filenames start with ! if in bangable folder
              request_image(img.src, dir: dir_path, bang_prefix: dir[0] != '_')
            end
          end
        end
      end
    end

    def local_path_for(src:, dir:, bang_prefix:)
      maybe_bang = bang_prefix ? '!' : nil
      fname = src.split('/')[-1].split('?')[0]

      filename = [maybe_bang, fname].compact.join
      ::File.join(dir, filename)
    end

    def request_image(src, dir:, bang_prefix:)
      req = Typhoeus::Request.new(src)

      # LATER: could stream if necessary... https://github.com/typhoeus/typhoeus#streaming-the-response-body
      req.on_complete do |response|
        bar.increment
        if response.success?
          path = local_path_for(src: src, dir: dir, bang_prefix: bang_prefix)
          ::File.write(path, response.body)
        elsif response.timed_out?
          puts "#{src}: Timed out".red
        elsif response.code == 0
          # Could not get an http response, something's wrong.
          puts "#{src}: Couldn't get response code: #{response.return_message}".red
        else
          # Received a non-successful http response.
          puts "#{src}: #{response.code}".red
        end
      end

      hydra.queue(req)
      @requests += 1
    end
  end
end