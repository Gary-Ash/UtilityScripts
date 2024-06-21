#!/usr/bin/env zsh
#*****************************************************************************************
# ocd.sh
#
# Update system software and clean macOS settings
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  28-Apr-2024  10:00pm
# Modified :  10-Jun-2024  9:32pm
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# load utilities from scripting libraries
#*****************************************************************************************
autoload get_sudo_password
autoload start_persistant_sudo
autoload stop_persistant_sudo

#*****************************************************************************************
# set a exit trap to make sure the persistent sudo thread is always cleaned up
#*****************************************************************************************
trap finish EXIT

finish() {
	if [[ -n $SUDO_PASSWORD ]]; then
		stop_persistant_sudo
	fi
}

#*****************************************************************************************
# kill applications
#*****************************************************************************************
kill-everything() {
	appsToKill=("Keyboard Maestro Engine" "Dock" "Safari" "Finder" "Slack" "ColorSnapper2" "Default Folder X" "Mona")

	for app in "${appsToKill[@]}"; do
		killall "$app" &>/dev/null
	done

	osascript <<"CLOSE_SCRIPT" &>/dev/null
tell application "System Events"
	set processList to ¬
		(name of every process where background only is false) as text

	set myFrontMost to name of first item of ¬
		(processes whose frontmost is true) as text

	repeat with processName in processList
		try
			if processName is not equal to myFrontMost then
				do shell script "Killall " & quoted form of processName
			end if
		end try
	end repeat
end tell
delay 1
CLOSE_SCRIPT
}

#-----------------------------------------------------------------------------------------
# SCRIPT MAIN LINE
#-----------------------------------------------------------------------------------------

#*****************************************************************************************
# parse the command line for arguments
#*****************************************************************************************
if [[ $# -gt 0 ]]; then
	cmd=$(echo "$1" | tr '[:upper:]' '[:lower:]')

	if [[ $cmd == "restart" ]]; then
	elif [[ $cmd == "off" ]]; then
	else
		echo "Unknown command option -- $cmd"
		exit 1
	fi
fi
export OCD_OPTION="$cmd"

defaults write com.apple.Safari IncludeInternalDebugMenu 1

SUDO_PASSWORD=$(get_sudo_password)
error_log="$TMPDIR/Error.txt"

kill-everything

cd ~ || return

#*****************************************************************************************
# brew
#*****************************************************************************************
if command -v brew &>/dev/null; then
	SUDO_PASSWORD=$(get_sudo_password)
	start_persistant_sudo "$SUDO_PASSWORD"
	sudo chmod -R 777 /Applications/* &>/dev/null
	stop_persistant_sudo

	brew update &>"$error_log"
	brew upgrade &>"$error_log"
	brew upgrade --cask &>"$error_log"
	brew autoremove &>"$error_log"
	brew cleanup &>"$error_log"
	rm -rf $(brew --cache) &>/dev/null

	SUDO_PASSWORD=$(get_sudo_password)
	start_persistant_sudo "$SUDO_PASSWORD"

	sudo chown -R root:wheel /opt/geedbla/* &>/dev/null
	sudo chown -R root:wheel /Applications/* &>/dev/null
	sudo chmod -R 755 /Applications/* &>/dev/null
	sudo xattr -cr /Applications/* &>/dev/null
	stop_persistant_sudo
fi

#*********************************************************************************
# ruby update
#*********************************************************************************
if command -v gem &>/dev/null; then
	gem update &>"$error_log"
	gem cleanup &>"$error_log"
fi

#*********************************************************************************
# python 3 update
#*********************************************************************************
if command -v pip3 &>/dev/null; then
	python3 -m pip install --upgrade --break-system-packages pip &>"$error_log"
	pip3 install -U --break-system-packages $(pip3 freeze | cut -d = -f 1) &>"$error_log"
fi

#*****************************************************************************************
# npm update
#*****************************************************************************************
if command -v npm &>/dev/null; then
	npm install -g npm@latest &>"$error_log"
fi

#*****************************************************************************************
pkill -f '.*GradleDaemon.*'
qlmanage -r &>/dev/null

find "$HOME" -name "Icon?" -exec chflags hidden {} \; &>/dev/null
#*****************************************************************************************
# clean my git projects
#*****************************************************************************************
raw=$(find "$HOME/Developer" -type d -name ".git")
raw+=$(find "$HOME/Documents" -type d -name ".git")

while read -r gitDir; do
	cd "$gitDir"
	git gc --aggressive --prune=now &>/dev/null
done < <(echo "${raw}")

find "$HOME/Developer" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null
find "$HOME/Documents" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null

find "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Preferencesc" -name "Keyboard Maestro Macros \(*.kmsync" -delete &>/dev/null
find "$HOME/Library/Application Support/AddressBook" -name "*.abbu.tbz" -delete &>/dev/null
find "/Users/Shared/CleanMyMac X/" -depth 1 ! -name ".licence" -exec rm -rfv {} \; &>/dev/null
find "$HOME/Sites" \( -name "Gemfile.lock" -or -name ".sass-cache" -or -name ".jekyll*" -or -name "_site" -or -name ".jekyll-metadata" \) -exec rm -rfv {} \; &>/dev/null

SUDO_PASSWORD=$(get_sudo_password)
start_persistant_sudo "$SUDO_PASSWORD"
sudo /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

load-simulator.pl &
sudo perl /opt/geedbla/scripts/sublime-snippets.pl --delete
#****************************************************************************************
# Pause Time Machine while updating and cleaning
#****************************************************************************************
sudo tmutil stopbackup
sudo tmutil disable

#*****************************************************************************************
# empty trash
#*****************************************************************************************
emulate sh -c 'sudo rm -rf ~/.Trash/* ' &>/dev/null
emulate sh -c 'sudo rm -rf /Volumes/*/.Trashes' &>/dev/null
emulate sh -c 'sudo rm -rf ~/.Trash /Volumes/*/.Trashes' &>/dev/null

rm -rf "$HOME/Library/Mobile Documents/com~apple~CloudDocs/.Trash"

#*****************************************************************************************
# clean up Time Machine local backups and turn it back on
#*****************************************************************************************
IFS=$'\n' snapshots=($(sudo tmutil listlocalsnapshots /Volumes/))
for snapshot in ${snapshots[*]}; do
	snapshot="${snapshot#com.apple.TimeMachine.*}"
	snapshot="${snapshot%% *}"
	sudo tmutil deletelocalsnapshots "$snapshot" &>/dev/null
done

#*****************************************************************************************
# notification center clean
#*****************************************************************************************
sudo killall "NotificationCenter"
sudo killall usernoted
rm -rf "$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/"* &>/dev/null

#*****************************************************************************************
# clean system Finder settings crap
#*****************************************************************************************
sudo find /usr/local -type f -name ".DS_Store" -delete &>/dev/null
sudo find /opt -type f -name ".DS_Store" -delete &>/dev/null

echo -n '' | pbcopy
sudo periodic daily weekly monthly

sudo /usr/bin/perl <<'PERL' &>/dev/null
#!/usr/bin/env perl
#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Foundation;

use POSIX qw(strftime);
use utf8;
use Encode qw(decode encode);
use JSON::PP;
use XML::Simple;
use File::Find;
use File::Path qw(remove_tree);
use DateTime;

#*****************************************************************************************
# globals
#*****************************************************************************************
our $HOME = $ENV{'HOME'};

our @plistKeysToDelete = (
    "NewBookmarksLocationUUID",                                       "RecentSearchStrings",                                           "FXRecentFolders",                                                                                                       "GoToField",
    "RecentApplications",                                             "RecentDocuments",                                               "RecentServers",                                                                                                         "Hosts",
    "ExpandedURLs",                                                   "last_textureFileName",                                          "FXRecentFolders",                                                                                                       "FXLastSearchScope",
    "GoToField",                                                      "NSNavPanel",                                                    "NSNavRecentPlaces",                                                                                                     "NSNavLastRootDirectory",
    "NSNavLastCurrentDirectory",                                      "RecentSearchStrings",                                           "LRUDocumentPaths",                                                                                                      "TSAOpenedTemplates.Pages",
    "NSReplacePboard",                                                "ExpandedURLs",                                                  "SelectedURLs",                                                                                                          "NSReplacePboard",
    "Apple CFPasteboard find",                                        "Apple CFPasteboard replace",                                    "Apple CFPasteboard general",                                                                                            "findHistory",
    "replaceHistory",                                                 "MGRecentURLPropertyLists",                                      "OakFindPanelOptions",                                                                                                   "Folder Search Options",
    "recentFileList",                                                 "RecentDirectories",                                             "NSRecentXCProjectDocuments",                                                                                            "last_dataFileName",
    "lastSpritesFolder",                                              "main.lastFileName",                                             "defaults.settingsAbsPath",                                                                                              "main.lastFileName",
    "DefaultCheckOutDirectory",                                       "RecentWorkingCopies",                                           "kProjectBasePath",                                                                                                      "LastOpenedScene",
    "ABBookWindowController-MainBookWindow-personListController",     "IDEFileTemplateChooserAssistantSelectedTemplateCategory",       "IDEFileTemplateChooserAssistantSelectedTemplateName",                                                                   "IDERecentEditorDocuments",
    "XCOpenWorkspaceDocuments",                                       "IDETemplateCompletionDefaultPath",                              "IDETemplateOptions",                                                                                                    "IDEDefaultPrimaryEditorFrameSizeForPaths",
    "IDEDocViewerLastViewedURLKey",                                   "IDESourceControlRecentsFavoritesRepositoriesUserDefaultsKey",   "Xcode3ProjectTemplateChooserAssistantSelectedTemplateCategory",                                                         "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateCategory",   "Xcode3TargetTemplateChooserAssistantSelectedTemplateName",      "Xcode3ProjectTemplateChooserAssistantSelectedTemplateSection",                                                          "recentFileList",
    "lastSpritesFolder",                                              "main.lastFileName",                                             "last_name",                                                                                                             "last_textureFileName",
    "findRecentPlaces",                                               "RecentWebSearches",                                             "recentSearches",                                                                                                        "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_iOS",   "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_tvOS", "SGTRecentFileSearches",                                                                                                 "IDEFileTemplateChooserAssistantSelectedTemplateSection",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_tvOS", "IDEFileTemplateChooserAssistantSelectedTemplateName_tvOS",      "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection3ProjectTemplateChooserAssistantSelectedTemplateName_macOS", "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection",    "DVTTextCompletionRecentCompletions",                            "GoToFieldHistory",                                                                                                      "HistoryColors",
    "recentSearches",                                                 "recentSearchHints",                                             "IDETemplateCompletionDefaultPath",                                                                                      "SHKRecentServices",
    "FavoriteColors",                                                 "LastSetWindowSizeForDocument",                                  "recentCatalogPaths",                                                                                                    "IDELastBreakpointActionClassName",
    "RecentFindStrings",                                              "IDEFileTemplateChooserAssistantSelectedTemplateName_iOS",       "RecentReplaceStrings",                                                                                                  "IDESwiftMigrationAssistantReviewFilesSelectedChoice",
    "IDERunActionSelectedTab",                                        "DVTIgnoredDevices",                                             "IBGlobalLastEditorDocumentClassName",                                                                                   "IBDocumentOutlineViewMode",
    "IDELibrary.lastSelectedLibraryExtensionIDByEditorID",            "IBGlobalLastEditorTargetRuntime",                               "CurrentAlertPreferencesSelection",                                                                                      "DVTRecentCustomColors",
    "IDEProvisioningTeamManagerLastSelectedTeamID",                   "BKRecentsLastCleared",                                          "BKPreviouslyOpenedBookIDs",                                                                                             "RecentMoveAndCopyDestinations",
    "DownloadsFolderListViewSettingsVersion",                         "recent_viewed",                                                 "RecentsArrangeGroupViewBy",                                                                                             "IDEAppChooserRecentApplications-My Mac",
    "RecentRegions",                                                  "IDEFileTemplateChooserAssistantSelectedTemplateName_macOS",     "lastSource",                                                                                                            "lastReplacement",
    "lastRegex",                                                      "TSARecentOpenedDocumentTimestamps",                             "TSAOpenedTemplates.Numbers",                                                                                            "RecentItemsData",
    "TSAOpenedTemplates.Pages"
);

our @itemsToDelete = (
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",                  0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3",                        0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ProjectsItems.sfl3",                          0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl3",                     0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl3",                          0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentHosts.sfl3",                            0],
    ["$HOME/Library/Preferences/com.googlecode.iterm2.private.plist",                                                                     0],
    ["$HOME/Library/Preferences/com.apple.dock.extra.plist",                                                                              0],
    ["$HOME/.proxyman-data",                                                                                                              0],
    ["$HOME/.hawtjni",                                                                                                                    0],
    ["$HOME/.konan",                                                                                                                      0],
    ["$HOME/.cocoapods",                                                                                                                  0],
    ["$HOME/.swiftpm",                                                                                                                    0],
    ["$HOME/.fastlane",                                                                                                                   0],
    ["$HOME/.subversion",                                                                                                                 0],
    ["$HOME/.node_modules",                                                                                                               0],
    ["$HOME/.android/",                                                                                                                   0],
    ["$HOME/.cache/",                                                                                                                     0],
    ["$HOME/.bash_history",                                                                                                               0],
    ["$HOME/.python_history",                                                                                                             0],
    ["$HOME/.zcompcache",                                                                                                                 0],
    ["$HOME/.zsh_history",                                                                                                                0],
    ["$HOME/.local",                                                                                                                      0],
    ["$HOME/.bundle",                                                                                                                     0],
    ["$HOME/.gem",                                                                                                                        0],
    ["$HOME/Library/Caches/Yarn",                                                                                                         0],
    ["$HOME/.oracle_jre_usage",                                                                                                           0],
    ["$HOME/.bash_sessions",                                                                                                              0],
    ["$HOME/.gradle",                                                                                                                     0],
    ["$HOME/.recently-used",                                                                                                              0],
    ["$HOME/.cmake",                                                                                                                      0],
    ["$HOME/.solargraph",                                                                                                                 0],
    ["$HOME/.TemporaryItems",                                                                                                             0],
    ["$HOME/.thumbnails",                                                                                                                 0],
    ["$HOME/.config/zsh/.zsh_sessions",                                                                                                   0],
    ["$HOME/.config/zsh/histfile",                                                                                                        1],
    ["$HOME/.config/zsh/.zsh_history",                                                                                                    1],
    ["$HOME/.config/zsh/zcompdump-*",                                                                                                     1],
    ["$HOME/triald-*.ips",                                                                                                                1],
    ["$HOME/.config/configstore",                                                                                                         0],
    ["/private/var/folders/sf/_p_7qs4n7gg_r4yrrrvmphd00000gn/C/us.zoom.ZoomAutoUpdater",                                                  0],
    ["$HOME/Library/Autosave Information",                                                                                                0],
    ["$HOME/Library/Caches/org.carthage.CarthageKit",                                                                                     0],
    ["$HOME/Library/Saved Application State",                                                                                             0],
    ["$HOME/Library/Application Support/Steam",                                                                                           0],
    ["$HOME/Library/Application Support/iLifeMediaBrowser",                                                                               0],
    ["$HOME/Library/Application Support/CrashReporter",                                                                                   0],
    ["$HOME/Library/Application Support/dmd",                                                                                             0],
    ["$HOME/Library/Application Support/iMovie",                                                                                          0],
    ["$HOME/Library/Application Support/CleanMyMac X HealthMonitor",                                                                      0],
    ["$HOME/Library/Application Support/CleanMyMac X Menu",                                                                               0],
    ["$HOME/Library/Application Support/Translation",                                                                                     0],
    ["$HOME/Library/Application Support/CleanMyMac X Menu",                                                                               0],
    ["$HOME/Library/Developer/CoreSimulator/Caches",                                                                                      0],
    ["$HOME/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory",                                                              0],
    ["$HOME/Library/Developer/Xcode/DocumentationCache",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/DocumentationIndex",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/Products",                                                                                            0],
    ["$HOME/Library/Caches/Homebrew",                                                                                                     0],
    ["$HOME/Library/Caches/Homebrew/Backup",                                                                                              0],
    ["/$HOME/Library/Cookies/Hocom.kapeli.dashdoc.binarycookies",                                                                         0],
    ["/$HOME/Library/Cookies/org.m0k.transmission.binarycookies",                                                                         0],
    ["/$HOME/Library/Caches/com.apple.dt.Xcode",                                                                                          0],
    ["$HOME/Library/Autosave Information",                                                                                                0],
    ["$HOME/Library/Application Support/CrashReporter",                                                                                   0],
    ["$HOME/Pictures/iSkysoft VideoConverterUltimate",                                                                                    0],
    ["$HOME/Movies/iSkysoft VideoConverterUltimate",                                                                                      0],
    ["$HOME/Library/Preferences/com.apple.LaunchServices",                                                                                0],
    ["$HOME/Library/Preferences/UITextInputContextIdentifiers.plist",                                                                     0],
    ["$HOME/Library/Preferences/com.apple.EmojiCache.plist",                                                                              1],
    ["$HOME/Library/Preferences/com.apple.EmojiPreferences.plist",                                                                        1],
    ["$HOME/Movies/Motion Templates.localized",                                                                                           0],
    ["$HOME/Movies/Untitled.fcpbundle",                                                                                                   0],
    ["$HOME/Movies/iMovie Library.imovielibrary",                                                                                         0],
    ["$HOME/Movies/iMovie Theater.theater",                                                                                               0],
    ["$HOME/Music/Audio Music Apps",                                                                                                      0],
    ["$HOME/Library/Application Support/kotlin",                                                                                          0],
    ["$HOME/Library/Application Support/Mozilla",                                                                                         0],
    ["$HOME/Library/Application Support/JetBrains",                                                                                       0],
    ["$HOME/Library/Application Support/Battle.net",                                                                                      0],
    ["$HOME/Library/Application Support/Steam",                                                                                           0],
    ["$HOME/Library/org.swift.swiftpm",                                                                                                   0],
    ["$HOME/Music/Logic",                                                                                                                 0],
    ["$HOME/Library/Cookies/com.apple.Safari.SearchHelper.binarycookies",                                                                 0],
    ["$HOME/Library/Application Support/iPhone Simulator",                                                                                0],
    ["$HOME/Library/Messages/Archive",                                                                                                    0],
    ["$HOME/Library/Messages/Attachments",                                                                                                0],
    ["$HOME/Library/Metadata/com.apple.IntelligentSuggestions",                                                                           1],
    ["$HOME/Library/Application Support/Xcode",                                                                                           1],
    ["$HOME/Library/Developer/Xcode/Archives",                                                                                            0],
    ["$HOME/Library/Developer/Xcode/snapshots",                                                                                           0],
    ["$HOME/Library/Developer/Xcode/UserData/*.xcuserstate",                                                                              1],
    ["$HOME/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory",                                                              0],
    ["$HOME/Library/Application Support/Alfred/usage.data",                                                                               1],
    ["$HOME/Library/Application Support/Sublime Merge/Local/Backup Session.sublime_session",                                              0],
    ["$HOME/Library/Application Support/Sublime Merge/Log",                                                                               0],
    ["$HOME/Library/Application Support/Sublime Merge/Cache",                                                                             1],
    ["$HOME/Library/Application Support/Sublime Text/Backup",                                                                             0],
    ["$HOME/Library/Application Support/Sublime Text/Cache",                                                                              1],
    ["$HOME/Library/Application Support/Sublime Text/Index",                                                                              1],
    ["$HOME/Library/Application Support/Sublime Text/Log",                                                                                0],
    ["$HOME/Library/Application Support/Sublime Text/Trash",                                                                              0],
    ["$HOME/Library/Application Support/Sublime Text/Local/Backup Auto Save Session.sublime_session",                                     0],
    ["$HOME/Library/Application Support/Sublime Text/Local/Backup Session.sublime_session",                                               0],
    ["$HOME/Library/Application Support/Sublime Text/Packages/User/Package Control.cache",                                                1],
    ["$HOME/Library/Application Support/Sublime Text (Safe Mode)",                                                                        0],
    ["$HOME/Library/Application Support/CallHistoryDB",                                                                                   0],
    ["$HOME/Library/Application Support/CallHistoryTransactions",                                                                         0],
    ["$HOME/Library/Caches/com.apple.Safari/Webpage Previews",                                                                            1],
    ["$HOME/Library/Caches/com.apple.Safari/Cache.*",                                                                                     1],
    ["$HOME/Library/Caches/com.apple.Safari/fsCachedData",                                                                                1],
    ["$HOME/Library/Caches/com.apple.Safari/WebKitCache",                                                                                 1],
    ["$HOME/Library/Caches/com.apple.Safari/Webpage Previews",                                                                            1],
    ["$HOME/Library/Safari/Configurations.plist.signed",                                                                                  1],
    ["$HOME/Library/Caches/com.apple.Safari/Cache.db",                                                                                    1],
    ["$HOME/Library/Safari/CloudBookmarksMigrationCoordinator",                                                                           0],
    ["$HOME/Library/Safari/Cloud*",                                                                                                       1],
    ["$HOME/Library/Safari/LastSession.plist",                                                                                            1],
    ["$HOME/Library/Safari/TopSites.plist",                                                                                               1],
    ["$HOME/Library/Safari/Downloads.plist",                                                                                              1],
    ["$HOME/Library/Safari/WebFeedSources.plist",                                                                                         1],
    ["$HOME/Library/Safari/SearchDescriptions.plist",                                                                                     1],
    ["$HOME/Library/Safari/RecentlyClosedTabs.plist",                                                                                     1],
    ["$HOME/Library/Preferences/test_network.plist",                                                                                      1],
    ["$HOME/Library/Preferences/com.apple.sharekit.recents.plist",                                                                        1],
    ["$HOME/Library/Preferences/com.trolltech.plist",                                                                                     1],
    ["$HOME/Library/Preferences/com.qtproject.plist",                                                                                     1],
    ["$HOME/Library/Application Support/Dash/Temp",                                                                                       1],
    ["$HOME/Library/Developer/Xcode/DocumentationCache",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/UserData/IB Support",                                                                                 0],
    ["$HOME/Library/Developer/CoreSimulator/Caches",                                                                                      0],
    ["$HOME/Library/Developer/Xcode/Products",                                                                                            0],
    ["$HOME/Library/Caches/com.apple.dt.Xcode",                                                                                           0],
    ["$HOME/Library/Containers/com.koolesache.ColorSnapper2/Data/Library/Caches/com.koolesache.ColorSnapper2",                            0],
    ["$HOME/Library/Application Support/Keyboard Maestro/Keyboard Maestro Recent Applications.plist",                                     0],
    ["$HOME/Library/Application Support/Keyboard Maestro/Keyboard Maestro Clipboards.kmchunked",                                          0],
    ["$HOME/Library/Colors/NSColorPanelSwatches.plist",                                                                                   1],
    ["$HOME/Library/Preferences/embeddedBinaryValidationUtility.plist",                                                                   1],
    ["$HOME/Library/Containers/com.apple.podcasts/Data/Library/Preferences/com.apple.podcasts.plist",                                     0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Sessions",                                                                 0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/*History*",                                                                0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Local Storage",                                                            0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Top Sites",                                                                0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Top Sites-journal",                                                        0],
    ["$HOME/Library/Preferences/diagnostics_agent.plist",                                                                                 0],
    ["$HOME/Library/Preferences/sharedfilelistd.plist",                                                                                   0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/History",                                                                 0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/History-journal",                                                         0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Top Sites",                                                               0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Top Sites-journal",                                                       0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Visited Links",                                                           0],
    ["/Library/Logs",                                                                                                                     1],
    ["/Library/Logs/DiagnosticReports",                                                                                                   1],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2",                                             0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2",                                             0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2Helper",                                       0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2Helper",                                       0],
    ["$HOME/Library/Containers/com.apple.iBooksX/Data/Documents/BCRecentlyOpenedBooksDB",                                                 0],
    ["$HOME/Library/Containers/com.runisoft.Video-Joiner-and-Merger/Data/Library/Preferences/com.runisoft.Video-Joiner-and-Merger.plist", 0],
    ["$HOME/Library/Containers/com.bridgetech.asset-catalog/Data/Library/Application Support/saved_asset_catalog_creator",                0],
    ["$HOME/Library/Caches/com.apple.Music/SubscriptionPlayCache/",                                                                       0],
    ["$HOME/Library/Application Support/iTerm2/SavedState/lock",                                                                          0],
);

#*****************************************************************************************
# script main line
#*****************************************************************************************
podcastapp();
texturePacker();
books();

plists();
deleteFilesAndFolders();
xcode();
sublimeText();
sublimeMerge();

#*****************************************************************************************
# Books
#*****************************************************************************************
sub books {
    my $now = DateTime->now;
    $now->set_time_zone("UTC");
    my $datestring = $now->strftime("%Y-%m-%dT%TZ");

    my $plistFile = "$HOME/Library/Containers/com.apple.iBooksX/Data/Library/Preferences/com.apple.iBooksX.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);

    if ($plist) {
        $plist->setObject_forKey_($datestring, "BKRecentsLastCleared");
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# Sublime Text
#*****************************************************************************************
sub sublimeText {
    my $filename     = "$HOME/Library/Application Support/Sublime Text/Local/Session.sublime_session";
    my @keysToDelete = ("auto_complete", "file_history", "replace", "find_state", "find_in_files", "project", "buffers", "command_palette", "expanded_folders" . "workspace_name", "folders", "console", "groups");

    if (-e $filename) {
        open(my $configFile, "<", $filename);
        my $json = do { local $/; <$configFile> };
        close($configFile);
        my $utf8 = encode("UTF-8", $json);

        my $config = decode_json($utf8);
        delete $config->{'workspaces'};
        delete $config->{'folder_history'};
        for my $key (@keysToDelete) {
            delete $config->{$key};
        }
        for my $key (@keysToDelete) {
            delete $config->{'settings'}->{'new_window_settings'}->{$key};
            delete $config->{'settings'}->{$key};
        }
        my $firstFlag = 1;
        my @windows   = @{ $config->{'windows'} };
        for my $window (@windows) {
            if ($firstFlag == 0) {
                undef $window;
            }
            else {
                $firstFlag = 0;
            }
        }
        for my $key (@keysToDelete) {
            delete $windows[0]->{$key};
        }

        my %newConsole = (
            "height" => 220.0,
        );

        $windows[0]->{'console'} = \%newConsole;
        $config->{'windows'}     = \@windows;
        $json                    = encode_json($config);
        open($configFile, ">:encoding(UTF-8)", $filename);
        print $configFile $json;
        close($configFile);
    }

    my $plistFile = "$HOME/Library/Preferences/com.sublimetext.4.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
    $plist->writeToFile_atomically_($plistFile, "0");
}

#*****************************************************************************************
# Sublime Merge
#*****************************************************************************************
sub sublimeMerge {
    my $filename     = "$HOME/Library/Application Support/Sublime Merge/Local/Session.sublime_session";
    my @keysToDelete = ("recent", "select_repository", "windows", "window_positions");

    if (-e $filename) {
        open(my $configFile, "<", $filename);
        my $json = do { local $/; <$configFile> };
        close($configFile);
        my $utf8 = encode("UTF-8", $json);

        my $config = decode_json($utf8);
        for my $key (@keysToDelete) {
            delete $config->{$key};
        }
        $config->{"project_dir"} = "$HOME/Developer";
        $json = encode_json($config);
        open($configFile, ">:encoding(UTF-8)", $filename);
        print $configFile $json;
        close($configFile);
    }

    my $plistFile = "$HOME/Library/Preferences/com.sublimemerge.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
    $plist->writeToFile_atomically_($plistFile, "0");
}

#*****************************************************************************************
# Texture Packer
#*****************************************************************************************
sub texturePacker {
    my $plistFile = "$HOME/Library/Preferences/de.code-and-web.TexturePacker.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist && $$plist) {
        my $keyNamesArray = $plist->allKeys();
        my $items         = $keyNamesArray->count;
        for (my $index = 0; $index < $items; ++$index) {
            my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
            if ($key =~ /[A-Za-z0-9\-\.]*Users/) {
                $plist->removeObjectForKey_($key);
            }
        }
        unlink($plistFile);
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# Podcast
#*****************************************************************************************
sub podcastapp {
    my $plistFile = "$HOME/Library/Containers/com.apple.podcasts/Data/Library/Preferences/com.apple.podcasts.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist && $$plist) {
        my $keyNamesArray = $plist->allKeys();
        my $items         = $keyNamesArray->count;
        for (my $index = 0; $index < $items; ++$index) {
            my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
            if ($key =~ /playState:.*/) {
                $plist->removeObjectForKey_($key);
            }
        }
        unlink($plistFile);
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# process the plists in the Preferences folder
#*****************************************************************************************
sub plists {
    `killall Dock Finder`;
    foreach my $plistFile (glob "$HOME/Library/Preferences/*.plist") {
        eval {
            my $plistData = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
            foreach my $key (@plistKeysToDelete) {
                $plistData->removeObjectForKey_($key);
            }
            $plistData->writeToFile_atomically_($plistFile, "0");
        };
    }
    find(\&processFiles, "$HOME/Library/Containers");
    find(\&processFiles, "$HOME/Library/SyncedPreferences");
}

#*****************************************************************************************
# delete junk from a list of file and folders
#*****************************************************************************************
sub deleteFilesAndFolders {
    my %removeTreeOptions = (
        safe      => 1,
        verbose   => 0,
        keep_root => 1
    );

    `killall Dock Finder`;
    for my $item (0 .. $#itemsToDelete) {
        my $i                         = "\"" . $itemsToDelete[$item][0] . "\"";
        my @actualFilesAndDirectories = glob $i;
        for my $delete (@actualFilesAndDirectories) {
            if (-f $delete) {
                unlink($delete);
            }
            else {
                $removeTreeOptions{keep_root} = $itemsToDelete[$item][1];
                remove_tree($delete, \%removeTreeOptions);
            }
        }
    }
    my $temp = $ENV{'TMPDIR'};
    $removeTreeOptions{keep_root} = 1;
    remove_tree($temp, \%removeTreeOptions);
}

#*****************************************************************************************
# Xcode settings
#*****************************************************************************************
sub xcode {
    my $plistFile = "$HOME/Library/Preferences/com.apple.dt.Xcode.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist) {
        my $options         = NSMutableDictionary->dictionary();
        my %templateOptions = (
            "languageChoice"         => "Swift",
            "bundleIdentifierPrefix" => "com.geedbla",
            "organizationName"       => "Gee Dbl A",
            "hasUITests"             => "true",
            "hasUnitTests"           => "true",
            "storyboardBased"        => "true",
            "appLifecycle"           => "Cocoa",
        );
        foreach my $key (keys %templateOptions) {
            $options->setObject_forKey_($templateOptions{$key}, $key);
        }
        $plist->setObject_forKey_($options,           "IDETemplateOptions");
        $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# process the plists in the Containers folder
#*****************************************************************************************
sub processFiles {
    if ($File::Find::name =~ /\.plist$/) {
        eval {
            my $plistData = NSMutableDictionary->dictionaryWithContentsOfFile_($File::Find::name);
            foreach my $key (@plistKeysToDelete) {
                $plistData->removeObjectForKey_($key);
            }

            my $valuesDic = $plistData->objectForKey_("values");
            if ($valuesDic && $$valuesDic) {
                my $valuesDicM = $valuesDic->mutableCopy;
                foreach my $key (@plistKeysToDelete) {
                    $valuesDicM->removeObjectForKey_($key);
                }
                $plistData->setObject_forKey_($valuesDicM, "values");
            }

            $plistData->writeToFile_atomically_($File::Find::name, "0");
        };
    }
}
PERL

osascript <<END
try
	tell application "Keyboard Maestro Engine" to quit
end try
(*****************************************************************************************
 * clean  Safari
 ****************************************************************************************)
 tell application "Safari"
	activate
	delay 0.5
	tell application "System Events" to tell process "Safari"
		keystroke "y" using {command down}
		delay 0.1
		activate
		set frontmost to true

		click menu item "Select All" of menu 1 of menu bar item "Edit" of menu bar 1
		delay 0.3
		activate
		set frontmost to true
		keystroke (ASCII character 127)

		delay 0.3
		activate
		set frontmost to true
		keystroke "y" using {command down}

		try
			click menu item "Sync iCloud History" of menu 1 of menu bar item "Debug" of menu bar 1
			delay 6
		end try

		activate
		set frontmost to true
		keystroke "q" using {command down}
	end tell
end tell

(*****************************************************************************************
 * clean  Mail
 ****************************************************************************************)
try
	tell application "Mail" to launch
	repeat while application "Mail" is not running
		delay 1
	end repeat
	delay 2
	tell application "System Events" to tell process "Mail"
		repeat
			try
				activate
				set frontmost to true
				click checkbox 1 of group 1 of window 1
				exit repeat
			end try
		end repeat
		click menu item "Erase Junk Mail" of menu 1 of menu bar item "Mailbox" of menu bar 1
		delay 1
		click button "Erase" of sheet 1 of window 1
		delay 1
		click menu item "In All Accounts…" of menu 1 of menu item "Erase Deleted Items" of menu 1 of menu bar item "Mailbox" of menu bar 1
		delay 1

		click button "Erase" of sheet 1 of window 1
		delay 1
		click menu item "Previous Recipients" of menu 1 of menu bar item "Window" of menu bar 1
		delay 1

		try
			if number of rows in table 1 of scroll area 1 of window 1 > 0 then
				delay 0.5
				keystroke tab
				delay 0.3
				keystroke "a" using {command down}
				delay 0.3
				keystroke tab
				delay 3
				keystroke space
			end if
		end try
		keystroke "w" using {command down}
		delay 2
		click menu item "Quit Mail" of menu 1 of menu bar item "Mail" of menu bar 1
	end tell
end try

(*****************************************************************************************
 * clean up slack
 ****************************************************************************************)
try
	tell application "Slack" to activate
	delay 0.5
	try
		set workspaces to 0

		tell application "System Events" to tell process "Slack"
			tell application "Slack" to activate
			keystroke "1" using {command down}

			delay 0.1

			repeat until workspaces > 20
				try
					tell application "Slack" to activate

					click menu item "All Unreads" of menu 1 of menu bar item "Go" of menu bar 1
					delay 0.1
					tell application "Slack" to activate

					repeat 30 times
						key code 53
						delay 0.01
					end repeat
					delay 0.1
					tell application "Slack" to activate

					click menu item "Select Next Workspace" of menu of menu item "Workspace" of menu of menu bar item "File" of menu bar 1
					set workspaces to workspaces + 1
				end try
			end repeat

			delay 0.1
			tell application "Slack" to activate
			keystroke "1" using {command down}
			delay 0.1
			click menu item "Close Window" of menu 1 of menu bar item "File" of menu bar 1
		end tell
	end try
end try

try
	if (system attribute "OCD_OPTION" as text) is not equal to "" then
		tell application "Slack" to quit
	end if
end try

(*****************************************************************************************
 * clean Marked 2
 ****************************************************************************************)
try
	tell application "Marked 2"
		activate
		tell application "System Events" to tell process "Marked 2"
			click menu item "Clear Menu" of menu 1 of menu item "Open Recent" of menu 1 of menu bar item "File" of menu bar 1
		end tell
		quit
	end tell
end try

(*****************************************************************************************
 * clean FaceTime
 ****************************************************************************************)
try
	tell application "FaceTime"
		activate
		tell application "System Events"
			click menu item "Remove all Recents" of menu of menu bar item "FaceTime" of menu bar of process "FaceTime"
		end tell
		quit
	end tell
end try


(*****************************************************************************************
 * clean Xcode
 ****************************************************************************************)
tell application "Xcode" to activate
tell application "System Events" to tell process "Xcode"
	set done to false
	repeat while done = false
		try
			click menu item "Clear Menu" of menu of menu item "Open Recent" of menu of menu bar item "File" of menu bar 1
			set done to true
		end try
	end repeat
end tell

repeat while application "Xcode" is running
	delay 1
	tell application "Xcode" to quit
end repeat

(*****************************************************************************************
 * clean Messages
 ****************************************************************************************)
try
	tell application "Messages" to activate
	delay 1
	tell application "System Events" to tell process "Messages"
		activate
		set frontmost to true

		delay 1
		try
			click menu item "All Messages" of menu 1 of menu bar item "View" of menu bar 1
		end try
	end tell

	set repFlag to 1
	repeat while repFlag = 1
		tell application "Messages"
			activate
			tell application "System Events" to tell process "Messages"
				try
					click menu item "Delete Conversation…" of menu 1 of menu bar item "Conversation" of menu bar 1
				end try

				try
					delay 0.5
					click button "Delete" of sheet 1 of window 1
				on error
					set repFlag to 0
				end try
			end tell
		end tell
	end repeat
	tell application "Messages" to quit
end try

(*****************************************************************************************
 * clean up Pastebot
 ****************************************************************************************)
try
	tell application "Pastebot" to quit
	delay 0.1
	tell application "Pastebot" to launch

	tell application "System Events" to tell process "Pastebot"
		set frontmost to true
		try
			delay 0.1
			tell application "Pastebot" to activate
			click menu item "Clear Clipboard" of menu 1 of menu bar item "Edit" of menu bar 1
			delay 0.2
			keystroke tab
			delay 0.1
			keystroke return
		end try
		delay 0.4
		tell application "Pastebot" to activate
		click menu item "Close Window" of menu 1 of menu bar item "File" of menu bar 1
	end tell
end try

(*****************************************************************************************
 * clean up ColorSnapper2
 ****************************************************************************************)
if (system attribute "OCD_OPTION" as text) is equal to "" then
	try
		tell application "ColorSnapper2" to activate
		repeat while application "ColorSnapper2" is not running
			delay 0.1
		end repeat

		repeat 4 times
			tell application "System Events" to tell process "ColorSnapper2"
				set frontmost to true
				key code 53
			end tell
		end repeat
	end try
end if

(*****************************************************************************************
 * clean up Finder windows
 ****************************************************************************************)
try
	tell application "Finder"
		activate
		repeat with w in (get every Finder window)
			activate w
			tell application "System Events" to tell process "Finder"
				keystroke "a" using {command down}
				delay 0.5
				key code 123
				keystroke "a" using {command down, option down}
				delay 0.5
			end tell
		end repeat

		set desktopBounds to bounds of window of desktop
		set w to round (((item 3 of desktopBounds) - 1100) / 2) rounding as taught in school
		set h to round (((item 4 of desktopBounds) - 1000) / 2) rounding as taught in school
		set finderBounds to {w, h, 1100 + w, 1000 + h}

		try
			set (bounds of window 1) to finderBounds
		on error
			make new Finder window to home
		end try
		set (bounds of window 1) to finderBounds
		close every window

		tell application "System Events" to tell process "Finder"
			click menu item "Clear Menu" of menu of menu item "Recent Items" of menu of menu bar item 1 of menu bar 1
			click menu item "Clear Menu" of menu of menu item "Recent Folders" of menu of menu bar item "Go" of menu bar 1
		end tell
	end tell
end try

(*****************************************************************************************
 * clean up DerivedData
 ****************************************************************************************)
set p to (system attribute "HOME" as string) & "/Library/Developer/Xcode/DerivedData"
try
	tell application "Finder" to delete ((POSIX file p) as alias)
	tell application "Finder" to empty trash
end try
END

#*****************************************************************************************
# clear the icon cache
#*****************************************************************************************
sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -or -name com.apple.iconservices \) -exec rm -rfv {} \; &>/dev/null
sudo touch /Applications/* &>/dev/null

find "$HOME/Library/Application Support/com.stclairsoft.DefaultFolderX5/Default Set" ! -name "DefaultFolders.plist" -delete &>/dev/null

rm -rf "$HOME/Movies/Motion\ Templates" &>/dev/null
rm -f "$error_log"
sudo find /private/ -type d -name "org.llvm*" -exec rm -rf {} \; &>/dev/null
sudo find /private/ -type d -name "com.apple.dt.Xcode" -exec rm -rf {} \; &>/dev/null

#*****************************************************************************************
# keep permissions in the /Applications folder good
#*****************************************************************************************
sudo chown -R root:wheel /Applications/* &>/dev/null
sudo chmod -R 755 /Applications/* &>/dev/null
sudo xattr -cr /Applications/* &>/dev/null

CACHE=$(getconf DARWIN_USER_CACHE_DIR)
sudo rm -rf ${CACHE}com.apple.DeveloperTools &>/dev/null
sudo rm -rf ${CACHE}org.llvm.clang.$(whoami)/ModuleCache &>/dev/null
sudo rm -rf ${CACHE}org.llvm.clang/ModuleCache &>/dev/null
sudo find "$HOME/Library/Caches" -type d -name "com.apple.dt.*" -exec rm -rf {} \; &>/dev/null

DTMP=$(getconf DARWIN_USER_TEMP_DIR)
sudo find "$DTMP" -name "*.swift" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "ibtool*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "*IBTOOLD*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "sources-*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "com.apple.test.* " -exec rm -rfv {} \; &>/dev/null

rm -rf ${DTMP}xcrun_db &>/dev/null

printf "\ec\e[3J"
dscacheutil -flushcache &>/dev/null
sudo /usr/libexec/xpchelper --rebuild-cache &>/dev/null
sudo update_dyld_shared_cache -force &>/dev/null
sudo purge &>/dev/null

find "$HOME/Library/Developer" -type d -name "[A-Za-z0-9]* Device Logs" -exec rm -rfv {} \; &>/dev/null
sqlite3 "$(find "$HOME/Library/Mail" -name "Envelope Index")" vacuum

#****************************************************************************************
# Restart Time Machine while updating and cleaning
#****************************************************************************************
sudo tmutil enable &>/dev/null

#*****************************************************************************************
# clean the font cache
#*****************************************************************************************
if [[ $OCD_OPTION == "restart" ]] || [[ $OCD_OPTION == "off" ]]; then
	sudo atsutil databases -remove &>/dev/null
	atsutil server -shutdown &>/dev/null
	atsutil server -ping &>/dev/null
fi

defaults write com.apple.finder DownloadsFolderListViewSettingsVersion 1

cat <<"XCODE_BREAKPOINTS" >"$HOME/Library/Developer/Xcode/UserData/xcdebugger/Breakpoints_v2.xcbkptlist"
<?xml version="1.0" encoding="UTF-8"?>
<Bucket
   uuid = "UserGlobalBreakpointBucket"
   type = "2"
   version = "2.0">
   <Breakpoints>
      <BreakpointProxy
         BreakpointExtensionID = "Xcode.Breakpoint.SymbolicBreakpoint">
         <BreakpointContent
            uuid = "E29DF884-B98D-4E34-B697-EB011F81DBA2"
            shouldBeEnabled = "No"
            nameForDebugger = "AutolayoutBreakpoint"
            ignoreCount = "0"
            continueAfterRunningActions = "Yes"
            symbolName = "UIViewAlertForUnsatisfiableConstraints"
            moduleName = "">
            <Actions>
               <BreakpointActionProxy
                  ActionExtensionID = "Xcode.BreakpointAction.ShellCommand">
                  <ActionContent
                     command = "/opt/bin/geedbla/wtf-autolayout.py"
                     arguments = "@(NSString *)[(id)$arg2 description]@"
                     waitUntilDone = "NO">
                  </ActionContent>
               </BreakpointActionProxy>
            </Actions>
            <Locations>
            </Locations>
         </BreakpointContent>
      </BreakpointProxy>
      <BreakpointProxy
         BreakpointExtensionID = "Xcode.Breakpoint.SwiftErrorBreakpoint">
         <BreakpointContent
            uuid = "D00820A6-4EEF-469A-AAA1-32E5314B9C3A"
            shouldBeEnabled = "No"
            ignoreCount = "0"
            continueAfterRunningActions = "No">
         </BreakpointContent>
      </BreakpointProxy>
   </Breakpoints>
</Bucket>
XCODE_BREAKPOINTS
rm -f "${HISTFILE}" &>/dev/null

defaults delete com.apple.Safari IncludeInternalDebugMenu

mkdir -p "$XDG_CACHE_HOME/zsh"
#*****************************************************************************************
# clean Z the directory tool
#*****************************************************************************************
if [[ -n"_Z_DATA" ]]; then
	rm -rf "$_Z_DATA" &>/dev/null
	touch "$_Z_DATA" &>/dev/null
fi

if [[ $OCD_OPTION == "" ]]; then
	finish
	history -p
	perl /opt/geedbla/scripts/startup-banner.pl --light
	osascript <<"END2"
try
    tell application "System Events" to tell process "ColorSnapper2"
        set frontmost to true
        key code 53
    end tell
end try
try
    tell application "Keyboard Maestro Engine" to launch
    try
		repeat while application "Keyboard Maestro Engine"  is not running
			delay 0.01
		end repeat
	end try
    tell application "Keyboard Maestro Engine" to activate
	tell application "System Events" to tell process "Keyboard Maestro"
			click menu item "Close" of menu 1 of menu bar item "File" of menu bar 1
	end tell
end try

set volume output volume 50 with output muted --100%
set volume without output muted

(*****************************************************************************************
 * clean up desktop selection
 ****************************************************************************************)
tell application "System Events"
    tell application "Spotlight" to activate
    click group 1 of scroll area 1 of application process "Finder"
end tell
END2
fi

#*****************************************************************************************
# Prepare for shutdown or restart
#*****************************************************************************************
if [[ $OCD_OPTION == "restart" ]]; then
	nohup osascript <<"RESTART" &>/dev/null &
delay 0.05
tell application "Finder" to restart
RESTART
elif [[ $OCD_OPTION == "off" ]]; then
	nohup osascript <<"SHUTDOWN" &>/dev/null &

delay 0.05
tell application "Finder" to shut down
SHUTDOWN
fi

if [[ $OCD_OPTION == "restart" ]] || [[ $OCD_OPTION == "off" ]]; then
	killall Terminal &>/dev/null
	killall iTerm &>/dev/null
fi
