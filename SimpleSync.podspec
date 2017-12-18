#
# Be sure to run `pod lib lint SimpleSync.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SimpleSync'
  s.version          = '0.1.5'
  s.summary          = 'SimpleSync is a library that can be used to sync core data values with server database using REST API.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
SimpleSync is a library that can be used to sync CoreData with server database using REST API. This makes displaying values in a UITableView very easy using NSFetchedResultsController.
                       DESC

  s.homepage         = 'https://github.com/NicholasMata/SimpleSync'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'NicholasMata' => 'NicholasMata94@gmail.com' }
  s.source           = { :git => 'https://github.com/NicholasMata/SimpleSync.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '9.0'

  s.source_files = 'SimpleSync/Classes/**/*'
  
  # s.resource_bundles = {
  #   'SimpleSync' => ['SimpleSync/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'UIKit'
  s.dependency 'Alamofire', '~> 4.3'
end
