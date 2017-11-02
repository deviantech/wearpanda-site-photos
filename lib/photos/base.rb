module Photos
  class ProcessingError < StandardError; end

  class << self

    def for_path(path, name: nil)
      name ||= File.basename(path)

      klass = case name
      when /header/ then Photos::Header
      when /editorial/ then Photos::Editorial
      else Photos::Product
      end

      klass.new(path, name)
    end
  end

  class Base

    attr_accessor :path, :name
    def initialize(path, name)
      @path = path
      @name = name
    end

    def validate!
      check_min_sizes
      check_ratio if respond_to?(:expected_w_to_h)

      App.log.debug "\tPhoto #{name} is valid"
    rescue ProcessingError => e
      App.warn name, error: e
    end

    def process!
      validate!

      resize_to_dimensions!
      optimize!
    rescue ProcessingError => e
      App.warn name, error: e
    end

    private

    def min_height
      2048
    end

    def min_width
      2048
    end

    def max_size
      2048
    end

    def image
      @image ||= MiniMagick::Image.new(path)
    end

    def check_ratio
      (w, h) = image.dimensions
      w_to_h = w.to_f / h
      unless equal_within_error?(w_to_h, expected_w_to_h)
        raise ProcessingError, "#{name}: dimensions #{w}x#{h} give ratio #{w_to_h}, expected #{expected_w_to_h}"
      end
    end

    def check_min_sizes
      (w, h) = image.dimensions
      if min_width && w < min_width
        if name =~ App::UPTO_REGEX
          App.log.debug "#{name} is shorter than recommended (#{min_width}), but allowing it because it's an upto image".yellow
        else
          binding.pry
          raise(ProcessingError, "#{name}: width #{w} smaller than min allowed (#{min_width})")
        end
      end

      if min_height && h < min_height
        if name =~ App::UPTO_REGEX
          App.log.debug "#{name} is shorter than recommended (#{min_height}), but allowing it because it's an upto image".yellow
        else
          raise(ProcessingError, "#{name}: height #{h} smaller than min allowed (#{min_height})")
        end
      end
    end

    def resize_to_dimensions!
      if image.dimensions.any? {|d| d > max_size }
        App.log.info "\t#{App.dry? ? 'Would shrink' : 'Shrinking'} #{name} from #{image.dimensions} to max side length of #{max_size}".cyan
        image.resize("#{max_size}x#{max_size}") unless App.dry?
      end
    end

    def optimize!
      @@optim ||= ImageOptim.new(pngout: false) # Couldn't find binary
      @@optim.optimize_image!(path) unless App.dry?
      App.log.debug "\t#{App.dry? ? 'Would optimize' : 'Optimized'} #{name}"
    end

    def equal_within_error?(given, expected)
      places = expected.to_s.split('.')[1].length
      allowed_variance = 1.0 / (10 ** places)
      adjusted = round_to_places(given, places)

      (adjusted <= expected + allowed_variance) && (adjusted >= expected - allowed_variance)
    end

    def round_to_places(float, places = 3)
      (float.to_f * 10 ** places).round.to_f / (10** places)
    end
  end
end