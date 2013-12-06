class LocationDecoder

  def self.decode(str)
    require 'cgi'

    l2 = str[0].to_i
    l3 = str[1...str.length]
    l4 = (1.0 * l3.length / l2).floor
    l5 = l3.length % l2
    l6 = []
    l7 = 0

    while (l7 < l5) do
      if (!l6[l7])
        l6[l7] = ""
      end
      l6[l7] = l3[((l4 + 1) * l7)...((l4 + 1) * (l7 + 1))]
      l7 += 1
    end
    l7 = l5 
    while (l7 < l2) do
      l6[l7] = l3[
        ((l4 * (l7 - l5)) + ((l4 + 1) * l5))...
        ((l4 * (l7 - l5)) + ((l4 + 1) * l5)) + l4
      ]
      l7 += 1
    end
    l8 = ''
    l7 = 0
    while (l7 < l6[0].length) do
      l10 = 0
      while (l10 < l6.length) do
        l8 = (l8 + l6[l10][l7]) if (l7 < l6[l10].length)
        l10 += 1
      end
      l7 += 1
    end
    l8 = CGI::unescape(l8)
    l9 = ''
    l7 = 0
    while (l7 < l8.length) do
      if (l8[l7] == '^')
        l9 = (l9 + "0")
      else
        l9 = (l9 + l8[l7])
      end
      l7 += 1
    end
    l9 = l9.gsub('+', ' ')
    return l9
  end
  
end
