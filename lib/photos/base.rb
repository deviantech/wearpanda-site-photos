module Photos
  class ProcessingError < StandardError; end

  class << self

    def for_path(path)
      klass = case path
      when /header/ then Photos::Header
      when /editorial/ then Photos::Editorial
      else Photos::Product
      end

      klass.new(path)
    end
  end

  class Base

    attr_accessor :path
    def initialize(path)
      @path = path
    end

    def validate!
      check_min_sizes
      check_ratio if respond_to?(:expected_w_to_h)

      App.log.debug "\tPhoto at #{path} is valid".green
    rescue ProcessingError => e
      App.warn path, error: e
    end

    def process
      validate!

      resize_to_dimensions
    rescue ProcessingError => e
      App.warn path, error: e
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
        raise ProcessingError, "#{path}: dimensions #{w}x#{h} give ratio #{w_to_h}, expected #{expected_w_to_h}"
      end
    end

    def check_min_sizes
      (w, h) = image.dimensions
      if min_width && w < min_width
        if path =~ App::UPTO_REGEX
          App.log.debug "#{path} is shorter than recommended (#{min_width}), but allowing it because it's an upto image".yellow
        else
          raise(ProcessingError, "#{path}: width #{w} smaller than min allowed (#{min_width})")
        end
      end

      if min_height && h < min_height
        if path =~ App::UPTO_REGEX
          App.log.debug "#{path} is shorter than recommended (#{min_height}), but allowing it because it's an upto image".yellow
        else
          raise(ProcessingError, "#{path}: height #{h} smaller than min allowed (#{min_height})")
        end
      end
    end

    def resize_to_dimensions
      if image.dimensions.any? {|d| d > max_size }
        App.log.info "\t#{App.dry? ? 'Would shrink' : 'Shrinking'} #{path} from #{image.dimensions} to max side length of #{max_size}".cyan
        image.resize("#{max_size}x#{max_size}") unless App.dry?
      end
    end

    def equal_within_error?(given, expected)
      places = expected.to_s.split('.')[1].length
      adjusted = round_to_places(given, places)

      adjusted == expected
    end

    def round_to_places(float, places = 3)
      (float.to_f * 10 ** places).round.to_f / (10** places)
    end
  end
end