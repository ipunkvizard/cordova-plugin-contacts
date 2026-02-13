# OutSystems Appium Tests Framework

References:

https://github.com/webdriverio/appium-boilerplate

https://github.com/igniteram/appium-webdriverio-typescript

https://medium.com/the-web-tub/testing-cordova-apps-with-appium-2b3b236e026b

# Setup
1. Have Appium installed
2. Run npm install to get the required dependencies

# Run Tests locally

To run the tests:
1. Start Appium server
    * either by using the command line or launching the server with the appium desktop application
    * have a device connected or emulator available
2. Run the command `npm run android` or `npm run ios`

After the tests run, you can then generate a report with allure:
`npm run report`

The generated report will be located in the **_allure-report_** folder


# Run Tests locally - Problem with Chromediver

Running tests in Android emulator: the chomedriver is not being recognized by appium.
To overcome this problem, follow the steps:
1. Install Appium desktop
2. Open appium desktop and click in "Advanced" tab
3. Scroll down. In the Chromedriver Binary Path parameter, paste the path to the chromedriver: "\<path>\chromedriver.exe"
4. Click "Start Server"

# AWS Device Farm

To run the tests in the device farm follow the steps: 
1. Create a run in aws
2. Upload your application (either _.ipa_ or _.apk_). Hit Next.
3. Upload the test bundle
    * Run the command `npm run bundleAws` and upload the generated `awsTests.zip` file.  
    * Hit Next.
4. Use the contents of the [/awsConfiguration_Android.yml](awsConfiguration_Android.yml) file for the script configuration on Android devices OR use the contents of the [/awsConfiguration_iOS.yml](awsConfiguration_iOS.yml) file for the script configuration on iOS devices
