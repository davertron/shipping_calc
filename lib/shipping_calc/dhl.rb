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

require 'rexml/document'
require 'net/http'
require 'net/https'
require 'uri'
include REXML

module ShippingCalc
  # Current version on their website is 1.0 and can be found in:
  # https://eCommerce.airborne.com/ApiLandingTest.asp . To get full access to
  # all their stuff you have to make sure they certify your application
  # against their live platform tests. The test bed should be enough to get
  # simple calculations.
  # Currently, only shipments made inside the US are available.

  class DHL

    # Obtains an estimate quote from the DHL site. 
    # <tt>params</tt> is a hash with all the settings for the shipment. They are:
    #
    # :*api_user*:: API access username, provided by DHL.
    # :*api_password*:: API access password, provided by DHL.
    # :*shipping_key*:: API shipping key, provided by DHL.
    # :*international_shipping_key*:: API shipping key, provided by DHL, used
      # for international quotes.
    # :*account_num*:: Account number, provided by DHL.
    # :*date*:: Date for the shipping in format YYYY-MM-DD (defaults to Time.now).
    # :*service_code*:: Service code defined in Rate Estimate Specification(E, N, S, G). 1030 and SAT are not supported yet. Defaults to G (ground service).
    # :*shipment_code*:: ShipmentType code defined in the Rate Estimate Specification. "P" for Package or "L" for Letter. Defaults to "P".
    # :*weight*:: Order's weight. If the shipment code is a "L" (letter) then the weight will be 0.
    # :*to_street*:: Recipient's street
    # :*to_zip*:: Recipient's zip code.
    # :*to_country*:: Recipient's country.
    # :*to_state*:: Recipient's state.
    # :*international*:: Whether or not the quote is international or not

    def quote(params)
      @international = params[:international]
      @xml = Document.new
      @xml << XMLDecl.new("1.0' encoding='UTF-8")
      raise ShippingCalcError.new("Invalid parameters") if params.nil?
      raise ShippingCalcError.new("Missing shipping parameters") unless params.keys.length >= 10
      auth(params[:api_user], params[:api_password])
      rate_estimate(params)
      request
    end

    private 

    # DHL gets the quote in 2 steps, the first one is authentication. This
    # generates the XML for that.
    def auth(api_user, api_password)
      # <eCommerce action="Request" version="1.1">
      #   <Requestor>
      #     <ID>username</ID>
      #     <Password>password</Password>
      #   </Requestor>
      # </eCommerce>
      ecommerce = Element.new "eCommerce"
      ecommerce.attributes["action"] = "Request"
      ecommerce.attributes["version"] = "1.1"

      user = Element.new "Requestor"
      user_id = Element.new "ID"
      user_id.text = api_user 

      user_pwd = Element.new "Password"
      user_pwd.text = api_password 

      user << user_id
      user << user_pwd

      ecommerce << user
      @xml << ecommerce
    end

    # After having the auth message ready, we create the RateEstimate request.
    #     shipping_key: API shipping key, provided by DHL.
    #     account_num: Account number, provided by DHL.
    #     date: Date for the shipping. Must be a Ruby "Time" object.
    #     service_code: Service code defined in Rate Estimate Specification
    #     (E, N, S, G). 1030 and SAT are not supported yet. Defaults to G
    #     (ground service).
    #     shipment_code: ShipmentType code defined in the Rate Estimate
    #     Specification. "P" for Package or "L" for Letter. Defaults to "P".
    #     weight: Order's weight. If the shipment code is a "L" (letter) then
    #     the weight will be 0.
    #     to_street: Recipient's street address.
    #     to_zip: Recipient's zip code.
    #     to_country: Recipient's country. Not used, currently DHL only supports US.
    #     to_state: Recipient's state.
    #     international: Whether you're getting an international quote or not
    def rate_estimate(params)
      if @international
        shipment = Element.new 'IntlShipment'
        shipment.attributes['action'] = 'RateEstimate'
        shipment.attributes['version'] = '1.0'
        
        credentials = Element.new 'ShippingCredentials'
        key = Element.new 'ShippingKey'
        key.text = params[:international_shipping_key]
        account = Element.new 'AccountNbr'
        account.text = params[:account_num]

        credentials << key
        credentials << account
        shipment << credentials

        shipment_details = Element.new 'ShipmentDetail'
        ship_date = Element.new 'ShipDate'
        ship_date.text = date(params[:date])
        shipment_details << ship_date

        service = Element.new 'Service'
        service_code = Element.new 'Code'
        service_code.text = service_code(params[:service_code])
        service << service_code
        shipment_details << service

        shipment_type = Element.new 'ShipmentType'
        type_code = Element.new 'Code'
        type_code.text = shipment_code(params[:shipment_code])
        shipment_type << type_code
        shipment_details << shipment_type

        weight = Element.new 'Weight'
        weight.text = weight(params[:weight], 'P')
        shipment_details << weight

        content_description = Element.new 'ContentDesc'
        content_description.text = 'Computer Parts'
        shipment_details << content_description

        shipment << shipment_details

        dutiable = Element.new 'Dutiable'
        dutiable_flag = Element.new 'DutiableFlag'
        dutiable_flag.text = 'Y'
        dutiable << dutiable_flag

        customs_value = Element.new 'CustomsValue'
        customs_value.text = '100'
        dutiable << customs_value
        shipment << dutiable

        billing = Element.new 'Billing'
        party = Element.new 'Party'
        party_code = Element.new 'Code'
        party_code.text = 'S'
        party << party_code
        billing << party
        duty_payment_type = Element.new 'DutyPaymentType'
        duty_payment_type.text = 'S'
        billing << duty_payment_type
        shipment << billing

        receiver = Element.new 'Receiver'
        address = Element.new 'Address'
        street = Element.new 'Street'
        street.text = params[:to_street]
        address << street
        city = Element.new 'City'
        city.text = params[:to_city]
        address << city
        state = Element.new 'State'
        state.text = params[:to_state]
        address << state
        country = Element.new 'Country'
        country.text = params[:to_country]
        address << country
        postal_code = Element.new 'PostalCode'
        postal_code.text = params[:to_zip]
        address << postal_code
        receiver << address

        shipment << receiver
      else
        # <Shipment action="RateEstimate" version="1.0">
        shipment = Element.new "Shipment"
        shipment.attributes["action"] = "RateEstimate"
        shipment.attributes["version"] = "1.0"

        # <ShippingCredentials>
        #   <ShippingKey>key</ShippingKey> 
        #   <AccountNbr>number</AccountNbr>
        # </ShippingCredentials>
        credentials = Element.new "ShippingCredentials"

        key = Element.new "ShippingKey"
        key.text = params[:shipping_key] 
        account = Element.new "AccountNbr"
        account.text = params[:account_num] 

        credentials << key
        credentials << account
        shipment << credentials

        # <ShipmentDetail>
        #   <ShiptDate>date</ShipDate>
        shipment_detail = Element.new "ShipmentDetail"
        ship_date = Element.new "ShipDate"   
        ship_date.text = date(params[:date])
        shipment_detail << ship_date

        # TODO: Implement SAT and 1030 services

        #   <Service>
        #     <Code>code</Code>
        #   </Service>
        service = Element.new "Service"
        service_code = Element.new "Code"
        service_code.text = service_code(params[:service_code])
        service << service_code

        shipment_detail << service

        #   <ShipmentType>
        #     <Code>code</Code>
        #   </ShipmentType>
        shipment_type = Element.new "ShipmentType"
        shipment_type_code = Element.new "Code"
        shipment_type_code.text = shipment_code(params[:shipment_code])
        shipment_type << shipment_type_code
        shipment_detail << shipment_type

        #   <Weight>weight</Weight>
        weight = Element.new "Weight"
        weight.text = weight(params[:weight], params[:shipment_code])

        # </ShipmentDetail>      
        shipment_detail << weight

        shipment << shipment_detail

        # <Billing>
        #   <Party>
        #     <Code>S</Code>
        #   </Party>
        # </Billing>
        billing = Element.new "Billing"
        billing_party = Element.new "Party"
        billing_party_code = Element.new "Code"

        # Since we're just doing some quick calulations we don't want to be
        # worrying about who's gonna send the package. Just make the calulations 
        # assuming the sender pays for the shipping.
        billing_party_code.text = "S"

        billing << billing_party << billing_party_code

        shipment << billing

        # <Receiver>
        #   <Address>
        #     <State>state</State>
        #     <Country>country</Country>
        #     <PostalCode>code</PostalCode>
        #   </Address>
        # </Receiver>
        receiver = Element.new "Receiver"
        receiver_addr = Element.new "Address"
        receiver_state = Element.new "State"
        receiver_country = Element.new "Country"
        receiver_zipcode = Element.new "PostalCode"

        receiver_state.text = state(params[:to_state])
        receiver_country.text = "US"
        receiver_zipcode.text = zip_code(params[:to_zip])

        receiver_addr << receiver_state
        receiver_addr << receiver_country
        receiver_addr << receiver_zipcode
        receiver << receiver_addr

        shipment << receiver
      end

      root = @xml.elements["eCommerce"]
      root.add shipment
    end

    # Sends the request to the web server and returns the response.
    def request
      #server = Net::HTTP.new("eCommerce.airborne.com", 443)
      server = Net::HTTP.new("eCommerce.airborne.com", 80)
      #path = "/ApiLandingTest.asp"
      path = "/ApiLanding.asp"
      data = @xml.to_s
      File.open('/home/david/Desktop/dhl_intl.xml', 'w') do |f|
        f.puts data
      end
      headers = { "Content-Type" => "text/xml"}
      #server.use_ssl = true
      resp = server.post(path, data, headers)
      price = parse_response(resp.body)
    end

    # Parses the server's response. Currently, it only returns the estimate
    # value of the shipping.
    def parse_response(resp)
      doc = Document.new(resp)

      find_error_and_raise(doc) if errors_exist?(doc)

      if @international
        result =  doc.elements["//IntlShipment/Result/Desc"].text 
      else
        result =  doc.elements["//Shipment/Result/Desc"].text 
      end
      
      if result == "Shipment estimate successful."
        if @international
          doc.elements["//IntlShipment/EstimateDetail/RateEstimate/TotalChargeEstimate"].text.to_f
        else
          doc.elements["//Shipment/EstimateDetail/RateEstimate/TotalChargeEstimate"].text.to_f
        end
      else
        raise ShippingCalcError.new(doc.to_s)
      end
    end

    def errors_exist?(response)
      not response.elements["//Faults"].nil?
    end

    def find_error_and_raise(response)
    error_code = response.elements["//Code"]

        # Special Services and Additional Protection are not supported        
      case error_code.text.to_i
          when 1000..1009 then msg = "Shipment Headers"
          when 4000..4004 then msg = "ShippingKey"
          when 4007       then msg = "Account Number"
          when 4195..4198 then msg = "Account Number"
          when 4100..4106 then msg = "Shipment Date"
          when 4108..4117 then msg = "Service Type (Code)"
          when 4118..4122 then msg = "Shipment Type Code"
          when 4123..4124 then msg = "Weight"
          when 4128..4131 then msg = "Dimensions"
          when 4116       then msg = "Billing Party (Code)"
          when 4147       then msg = "Billing Party (Code)"
          when 4149..4152 then msg = "Billing Account Number"
          when 4164..4166 then msg = "Receiver City"
          when 4167       then msg = "Receiver State"
          when 4164..4166 then msg = "Receiver City"
          when 4169       then msg = "Receiver Country"
          when 4170..4176 then msg = "Receiver Postal Code"
          else                 msg = "API Request"
      end

      raise ShippingCalcError.new("DHL Error #{error_code.text}: Invalid #{msg}")
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

    def shipment_code(code)
      ['P', 'L', 'O'].include?(code) ? code : 'P'
    end

    def service_code(code)
      ['E', 'N', 'S', 'G', 'IE'].include?(code) ? code : 'G'
    end

    def weight(w, type)
      if type == 'L'
        '0'
      else
        (w > 0 && w <= 150) ? w.to_s : (raise ShippingCalcError.new('Invalid weight - Must be between 1 and 150 lbs.'))
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
