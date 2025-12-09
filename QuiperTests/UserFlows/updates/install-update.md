# Update Installation

## Overview
When a new version of Quiper is available and has been downloaded, the user is prompted to install the update.

## User Flow

### Preconditions
- Quiper is running
- An update has been downloaded (either automatically or manually)
- Update file is ready to install

### Steps

1. **Update Prompt Appears**
   - User sees update prompt window appear
   - Window shows:
     - Current version number
     - New version number
     - Release notes/changelog
     - "Install and Restart" button
     - "Remind Me Later" button

2. **Review Update Information**
   - User reads the changelog
   - Sees what's new in the update
   - Decides whether to install now or later

3. **Choose to Install**
   - User clicks "Install and Restart"
   - System begins installation process:
     - Saves any necessary state
     - Closes Quiper
     - Runs installer
     - Launches new version

4. **App Restarts**
   - New version of Quiper launches
   - User continues working with updated version

### Alternative Flows

#### A1: Remind Me Later
- User clicks "Remind Me Later"
- Update prompt closes
- User will be reminded later (based on settings)
- Downloaded update remains available

#### A2: Automatic Download Disabled
- User has automatic updates enabled but not auto-download
- Sees "Update Available" notification
- Can click to download update
- Once downloaded, flow continues from step 1

### Expected Results
- Quiper updates to the new version
- All settings and data are preserved
- App restarts automatically after installation
- User can verify new version in About dialog

### Error Handling
- If installation fails, user sees error message
- Original version remains functional
- User can retry installation
- Option to download update again if file is corrupted
