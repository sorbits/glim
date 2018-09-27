module EncodeEmailFilter
  def encode_email(input)
    input.gsub(/(^mailto:)|\p{Alnum}+/) do |char|
      char.bytes.inject(String.new) do |result, byte|
        result << ($1 ? '&#%d;' : '%%%02X') % byte
      end
    end unless input.nil?
  end
end

Liquid::Template.register_filter(EncodeEmailFilter)
