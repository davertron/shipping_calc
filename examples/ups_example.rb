require 'rubygems'
require File.dirname(__FILE__) + '/../lib/shipping_calc'
require 'yaml'
require 'rbconfig'
include ShippingCalc

# This example requires you to have a .ups_info.yml file in your home dir to
# gather the login data. Check the Test secion in README.txt for more information.
begin
  os = Config::CONFIG["host_os"]
  if os =~ /darwin/
    auth_info = YAML.load_file("/Users/#{ENV["USER"]}/.ups_info.yml")
    else      
    auth_info = YAML.load_file("/home/#{ENV["USER"]}/.ups_info.yml")
  end
rescue Exception
  print "You don't have a .ups_info.yml file in your home directory. Please
read the \"Test\" section in README.txt.\n"
  exit
end

api_user = auth_info["api_user"]
api_pwd = auth_info["api_password"]
api_key = auth_info["shipping_key"]

opts = { 
  :api_user => api_user,
  :api_password => api_pwd,
  :shipping_key => api_key,
  :date => Time.now,
  :from_city => 'South Burlington',
  :from_state => 'VT',
  :from_country => 'US',
  :from_zip => '05403',
  :to_city => 'Shelburne',
  :to_zip => '05482',
  :to_state => 'VT',
  :to_country => 'US',
  :pickup_code => '01', # Daily Pickup, see lib/shipping_calc/ups.rb codes
  :package_code => '02', # UPS Letter, see lib/shipping_calc for details
  :weight_uom => 'LBS', # Unit of measure for package weight
  :package_weights => ['10']
}

u = UPS.new
q = u.quote(opts)
puts "Quote:"
q.each do |quote|
    puts "#{quote[0]} : #{quote[1]}"
end
