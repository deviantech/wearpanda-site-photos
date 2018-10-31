module Photos
  class Header < Base

    def expected_w_to_h
      2.5
    end

    def min_height
      nil
    end

    def min_width
      # 2048
      2002 # :/
    end

  end
end