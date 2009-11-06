# Copyright (c) 2008 Federico Builes

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'rubygems'
require 'rexml/document'
require 'net/http'
require 'hpricot'
include REXML

module ShippingCalc
  class UPS
    attr_accessor :test

    # Map for UPS shipping code numbers to text we should display
    SERVICE_CODES = {
        '01' => 'UPS Next Day Air',
        '02' => 'UPS Second Day Air',
        '03' => 'UPS Ground',
        '07' => 'UPS Worldwide Express (1 Day, includes brokerage fees)',
        '08' => 'UPS Worldwide Expedited (2-3 Days, includes brokerage fees)',
        '11' => 'UPS Standard (Up to 7 days, brokerage fees NOT included)',
        '12' => 'UPS 3 Day Select',
        '13' => 'UPS Next Day Air Saver',
        '14' => 'UPS Next Day Air Early A.M.',
        '54' => 'UPS Worldwide Express Plus (1 Day - Early Morning, includes brokerage fees',
        '59' => 'UPS 2nd Day Air A.M.',
        '65' => 'UPS Worldwide Saver'
    }

    def quote(params)
      @xml_pieces = []
      raise ShippingCalcError.new("Invalid parameters") if params.nil?
      raise ShippingCalcError.new("Missing shipping parameters") unless params.keys.length >= 14
      rate_estimate(params)
      make_request
    end

    # Use this to see the xml request you're sending and the xml response
    # you're receiving
    def set_debug(request_path, response_path)
        @debug = true
        @debug_request_path = request_path
        @debug_response_path = response_path
    end

    private 
    def rate_estimate(params)
      piece1 = Document.new
      piece1 << XMLDecl.new("1.0' encoding='UTF-8")
      access_request = Element.new 'AccessRequest'
      access_request.attributes['xml:lang'] = 'en-US'
      access_license_number = Element.new 'AccessLicenseNumber'
      access_license_number.text = params[:shipping_key]
      access_request << access_license_number
      user_id = Element.new 'UserId'
      user_id.text = params[:api_user]
      access_request << user_id
      password = Element.new 'Password'
      password.text = params[:api_password]
      access_request << password
      piece1 << access_request
      @xml_pieces << piece1

      piece2 = Document.new
      piece2 << XMLDecl.new("1.0' encoding='UTF-8")

      rating_service_selection_request = Element.new 'RatingServiceSelectionRequest'
      rating_service_selection_request.attributes['xml:lang'] = 'en-US'
      request = Element.new 'Request'
      transaction_reference = Element.new 'TransactionReference'
      customer_context = Element.new 'CustomerContext'
      # Note: this can be whatever we want, it just helps us synchronize
      # request/response pairs.
      customer_context.text = 'Rating and Service'
      transaction_reference << customer_context
      request << transaction_reference
      request_action = Element.new 'RequestAction'
      request_action.text = 'Rate'
      request << request_action
      request_option = Element.new 'RequestOption'
      # TODO: From the docs: "If the request does not provide an option, the
      # server defaults to rate behavior.  Rate = the server rates and
      # validates the shipment. This is the default behavior if an option is
      # not provided. Shop = The server validates the shipment, and returns
      # rates for all UPS products from the ShipFrom to the ShipTo addresses
      request_option.text = 'shop'
      request << request_option
      rating_service_selection_request << request

      pickup_type = Element.new 'PickupType'
      code = Element.new 'Code'
      # Valid codes are:
      # 01 - Daily Pickup
      # 03 - Customer Counter
      # 06 - One Time Pickup
      # 07 - On Call Air
      # 11 - Suggested Retail Rates
      # 19 - Letter Center
      # 20 - Air Service Center
      code.text = params[:pickup_code]
      pickup_type << code
      rating_service_selection_request << pickup_type

      shipment = Element.new 'Shipment'
      shipper = Element.new 'Shipper'
      address = Element.new 'Address'
      city = Element.new 'City'
      city.text = params[:from_city]
      address << city
      state_province_code = Element.new 'StateProvinceCode'
      state_province_code.text = params[:from_state]
      address << state_province_code
      country_code = Element.new 'CountryCode'
      country_code.text = params[:from_country]
      address << country_code
      postal_code = Element.new 'PostalCode'
      postal_code.text = params[:from_zip]
      address << postal_code
      shipper << address
      shipment << shipper

      ship_to = Element.new 'ShipTo'
      ship_to_address = Element.new 'Address'
      ship_to_city = Element.new 'City'
      ship_to_city.text = params[:to_city]
      ship_to_address << ship_to_city
      ship_to_state_province = Element.new 'StateProvinceCode'
      ship_to_state_province.text = params[:to_state]
      ship_to_address << ship_to_state_province
      ship_to_country_code = Element.new 'CountryCode'
      ship_to_country_code.text = params[:to_country]
      ship_to_address << ship_to_country_code
      ship_to_postal_code = Element.new 'PostalCode'
      ship_to_postal_code.text = params[:to_zip]
      ship_to_address << ship_to_postal_code
      ship_to << ship_to_address
      shipment << ship_to

      params[:package_weights].each do |package_weight|
        package = Element.new 'Package'
        packaging_type = Element.new 'PackagingType'
        code = Element.new 'Code'
        # Valid Codes are:
        # 00 = Unknown
        # 01 = UPS Letter
        # 02 = Package
        # 03 = Tube
        # 04 = Pak
        # 21 = Express Box
        # 24 = 25KG Box
        # 25 = 10KG Box
        # 30 = Pallet
        # 2a = Small Express Box
        # 2b = Medium Express Box
        # 2c = Large Express Box
        code.text = params[:package_code]
        packaging_type << code
        package << packaging_type
        xml_package_weight = Element.new 'PackageWeight'
        unit_of_measurement = Element.new 'UnitOfMeasurement'
        code = Element.new 'Code'
        # Can Either be LBS or KGS
        code.text = params[:weight_uom]
        unit_of_measurement << code
        xml_package_weight << unit_of_measurement
        weight = Element.new 'Weight'
        weight.text = package_weight
        xml_package_weight << weight
        package << xml_package_weight
        shipment << package
      end

      rating_service_selection_request << shipment

      customer_classification = Element.new 'CustomerClassification'
      code = Element.new 'Code'
      if params[:pickup_code] == '01'
          code.text = '01'
      elsif ['06', '07', '19', '20'].include? params[:pickup_code]
          code.text = '03'
      elsif params[:pickup_code] == '03'
          code.text = '04'
      else
          # Undefined in the docs...
          code.text = ''
      end
      customer_classification << code
      rating_service_selection_request << customer_classification
      
      piece2 << rating_service_selection_request
      @xml_pieces << piece2
    end

    # Sends the request to the web server and returns the response.
    def make_request
      if @test
          host = 'wwwcie.ups.com'
      else
          host = 'www.ups.com'
      end

      path = "/ups.app/xml/Rate"
      server = Net::HTTP.new(host, 443)
      data = @xml_pieces.collect{|p| p.to_s}.join("\n")
      if @debug
          File.open(@debug_request_path, 'w') do |file|
              file.puts data
          end
      end
      headers = { "Content-Type" => "text/xml"}
      server.use_ssl = true
      resp = server.post(path, data, headers)
      if @debug
          File.open(@debug_response_path, 'w') do |file|
              file.puts resp.body
          end
      end
      prices = parse_response(resp.body)
    end

    # Parses the server's response.
    def parse_response(resp)
      doc = Hpricot(resp)

      find_error_and_raise(doc) if errors_exist?(doc)

      codes = []
      doc.search('//ratedshipment/service/code') do |ele|
          codes << SERVICE_CODES[ele.innerHTML]
      end
      costs = []
      doc.search('//ratedshipment/totalcharges/monetaryValue') do |ele|
          costs << ele.innerHTML
      end

      quotes = codes.zip costs
    end

    def errors_exist?(response)
      not response.search('//responsestatuscode').innerHTML.to_i == 1
    end

    def find_error_and_raise(response)
      error_code = response.search('//errorcode')
      error_description = response.search('//errordescription')
      raise ShippingCalcError.new("UPS Error #{error_code.innerHTML.to_s}:
                                  #{error_description.innerHTML.to_s}")
    end

    def date(date)
      date ||= Time.now
      if date.kind_of?(String) && date =~ /\d{4}-\d{2}-\d{2}/ # Suppose it's valid
        return date
      end

      if date.strftime("%A") == "Sunday"    
        (date + 86400).strftime("%Y-%m-%d") # DHL doesn't ship on Sundays, add 1 day.
      else
        date.strftime("%Y-%m-%d")
      end
    end

    def state(s)
      valid_state?(s) ? s : (raise ShippingCalcError.new('Invalid state for recipient'))
    end

    def valid_state?(s)
      ShippingCalc::US_STATES.include?(s)
    end

    def zip_code(code)
      if code.class != Fixnum
        raise ShippingCalcError.new('Zip Code must be a number. Perhaps you are using a string?')
      end
      code.to_s =~ /\d{5}/ ? code.to_s : (raise ShippingCalcError.new('Invalid zip code for recipient'))
    end
  end
end
