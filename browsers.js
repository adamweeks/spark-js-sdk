'use strict';

/* eslint camelcase: [0] */

module.exports = {
  local: {
    Chrome: {}
  },

  sauce: {
    // Reminder: the first item in this object is used by pipeline builds
    sl_chrome_latest_osx11: {
      base: 'SauceLabs',
      platform: 'OS X 10.11',
      browserName: 'chrome',
      version: 'latest'
    },
    sl_chrome_latest_win7: {
      base: 'SauceLabs',
      platform: 'Windows 7',
      browserName: 'chrome',
      version: 'latest'
    },
    sl_firefox_latest_win7: {
      base: 'SauceLabs',
      platform: 'Windows 7',
      browserName: 'firefox',
      version: 'latest'
    }
  }
};
