#!/bin/sh


###
#
#            Name:  google_chrome_install_latest.sh
#     Description:  This script downloads and installs the latest version
#					Google Chrome and enables auto-updates. Hannes Juutilainen
#					created the python source enabling auto-updates.
#          Author:  Stephen Weinstein
#         Created:  2018-01-16
#   Last Modified:  2018-02-05
#
###

SERVICE='Google Chrome'

# Check to see if Google Chrome is installed
if [ -e /Applications/Google\ Chrome.app ]
then 
  echo "Google Chrome Present"
  chrome_status=true
fi

# Check to see if Google Chrome is open
if pgrep -xq -- "${SERVICE}"; then
    echo "Google Chrome is running... Please close to upgrade."
else
    echo "Google Chrome is not running"
    if [ "$chrome_status" = true ] ; then
      echo "Removing Google Chrome..."
      rm -rif "/Applications/Google Chrome.app"
      echo "Google Chrome Removed."
    fi
    echo "Google Chrome not present..."
    echo "Installing Google Chrome..."

    mkdir ~/googlechrome_temp
    cd ~/googlechrome_temp
    # Installing Google Chrome
    curl -L -o googlechrome.dmg "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg"
    hdiutil mount -nobrowse googlechrome.dmg
    cp -R "/Volumes/Google Chrome/Google Chrome.app" /Applications
    hdiutil unmount "/Volumes/Google Chrome"

    mounteddisk=`diskutil list | grep "Chrome"`
    diskname=`echo $mounteddisk | awk '{print $7}'`
    echo $diskname

    diskutil eject /dev/$diskname

    rm googlechrome.dmg
    rmdir ~/googlechrome_temp
fi


## Enable auto-updates
python - <<END

#!/usr/bin/env python
# encoding: utf-8
"""
chrome-enable-autoupdates.py

This script enables system wide automatic updates for Google Chrome.
It should work for Chrome versions 18 and later. No configuration needed
as this is originally intended as a munki postinstall script.

Created by Hannes Juutilainen, hjuutilainen@mac.com

History:

2015-09-25, Niklas Blomdalen
- Modifications to include old KeystoneRegistration installation (python version)

2014-11-20, Hannes Juutilainen
- Modifications for Chrome 39

2012-08-31, Hannes Juutilainen
- Added --force flag to keystoneInstall as suggested by Riley Shott

2012-05-29, Hannes Juutilainen
- Added more error checking

2012-05-25, Hannes Juutilainen
- Added some error checking in main

2012-05-24, Hannes Juutilainen
- First version

"""

import sys
import os
import getopt
import subprocess
import plistlib

chromePath = "/Applications/Google Chrome.app"
infoPlistPath = os.path.realpath(os.path.join(chromePath, 'Contents/Info.plist'))
brandPath = "/Library/Google/Google Chrome Brand.plist"
brandKey = "KSBrandID"
tagPath = infoPlistPath
tagKey = "KSChannelID"
versionPath = infoPlistPath
versionKey = "KSVersion"


class Usage(Exception):
    def __init__(self, msg):
        self.msg = msg


def chromeIsInstalled():
    """Check if Chrome is installed"""
    if os.path.exists(chromePath):
        return True
    else:
        return False


def chromeVersion():
    """Returns Chrome version"""
    infoPlist = plistlib.readPlist(infoPlistPath)
    bundleShortVersion = infoPlist["CFBundleShortVersionString"]
    return bundleShortVersion


def chromeKSUpdateURL():
    """Returns KSUpdateURL from Chrome Info.plist"""
    infoPlist = plistlib.readPlist(infoPlistPath)
    KSUpdateURL = infoPlist["KSUpdateURL"]
    return KSUpdateURL


def chromeKSProductID():
    """Returns KSProductID from Chrome Info.plist"""
    infoPlist = plistlib.readPlist(infoPlistPath)
    KSProductID = infoPlist["KSProductID"]
    return KSProductID


def keystoneRegistrationFrameworkPath():
    """Returns KeystoneRegistration.framework path"""
    keystoneRegistration = os.path.join(chromePath, 'Contents/Versions')
    keystoneRegistration = os.path.join(keystoneRegistration, chromeVersion())
    keystoneRegistration = os.path.join(keystoneRegistration, 'Google Chrome Framework.framework')
    keystoneRegistration = os.path.join(keystoneRegistration, 'Frameworks/KeystoneRegistration.framework')
    return keystoneRegistration


def keystoneInstall():
    """Install the current Keystone"""
    installScript = os.path.join(keystoneRegistrationFrameworkPath(), 'Resources/ksinstall')
    if not os.path.exists(installScript):
        installScript = os.path.join(keystoneRegistrationFrameworkPath(), 'Resources/install.py')
    keystonePayload = os.path.join(keystoneRegistrationFrameworkPath(), 'Resources/Keystone.tbz')
    if os.path.exists(installScript) and os.path.exists(keystonePayload):
        retcode = subprocess.call([installScript, '--install', keystonePayload, '--force'])
        if retcode == 0:
            return True
        else:
            return False
    else:
        print >> sys.stderr, "Error: KeystoneRegistration.framework not found"
        return False


def removeChromeFromKeystone():
    """Removes Chrome from Keystone"""
    ksadmin = "/Library/Google/GoogleSoftwareUpdate/GoogleSoftwareUpdate.bundle/Contents/MacOS/ksadmin"
    ksadminProcess = [  ksadmin, '--delete', '--productid',  chromeKSProductID()]
    retcode = subprocess.call(ksadminProcess)
    if retcode == 0:
        return True
    else:
        return False


def registerChromeWithKeystone():
    """Registers Chrome with Keystone"""
    ksadmin = "/Library/Google/GoogleSoftwareUpdate/GoogleSoftwareUpdate.bundle/Contents/MacOS/ksadmin"
    if os.path.exists(ksadmin):
        ksadminProcess = [ksadmin,
                        '--register',
                        '--preserve-tttoken',
                        '--productid',          chromeKSProductID(),
                        '--version',            chromeVersion(),
                        '--xcpath',             chromePath,
                        '--url',                chromeKSUpdateURL(),
                        '--tag-path',           tagPath,
                        '--tag-key',            tagKey,
                        '--brand-path',         brandPath,
                        '--brand-key',          brandKey,
                        '--version-path',       versionPath,
                        '--version-key',        versionKey]
        retcode = subprocess.call(ksadminProcess)
        if retcode == 0:
            return True
        else:
            return False
    else:
        print >> sys.stderr, "Error: %s doesn't exist" % ksadmin
        return False


def main(argv=None):
    if argv is None:
        argv = sys.argv
    try:
        # Check for root
        if os.geteuid() != 0:
            print >> sys.stderr, "This script must be run as root"
            return 1

        if not chromeIsInstalled():
            print >> sys.stderr, "Error: Chrome is not installed on this computer"
            return 1
        if keystoneInstall():
            print "Keystone installed"
        else:
            print >> sys.stderr, "Error: Keystone install failed"
            return 1
        if registerChromeWithKeystone():
            print "Registered Chrome with Keystone"
            return 0
        else:
            print >> sys.stderr, "Error: Failed to register Chrome with Keystone"
            return 1

    except Usage, err:
        print >>sys.stderr, err.msg
        print >>sys.stderr, "for help use --help"
        return 2


if __name__ == "__main__":
    sys.exit(main())
END






exit 0


