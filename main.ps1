# Configuration
$browser = "Chrome" # other options are "Firefox" and "Edge"
$maximized = $false # set to True if you want the browser to start maximized
$keyWord = "z"
$sleepTime = 2 # time in seconds to sleep before checking messages again
$longSleep = 20

$sentFile = "$PSScriptRoot\WorkingDirectory\sentFile.txt"
if (-not (Test-Path $sentFile) ) { $null = New-Item -ItemType File -Path $sentFile -Force }
$notSentFile = "$PSScriptRoot\WorkingDirectory\notSentFile.txt"
if (-not (Test-Path $notSentFile) ) { $null = New-Item -ItemType File -Path $notSentFile -Force }

# $fileName = Read-Host -Prompt "IP File Path"
# $ipList = Get-Content -Path $fileName
# $ips = $ipList.length - 1

if ($null -eq $Driver) {
    $arguments = @()
    if ($maximized) { $arguments += 'start-maximized' }
    if ($browser -eq "edge") {
        $Driver = Start-SeEdge -Arguments $arguments -Quiet
    }
    elseif ($browser -eq "Firefox") {
        $Driver = Start-SeFirefox -Arguments $arguments -Quiet
    }
    else {
        $Driver = Start-SeChrome -Arguments $arguments -Quiet
    }
    Enter-SeUrl "https://www.discord.com/login" -Driver $Driver

    Write-Host -NoNewLine 'Press any key to continue...';
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}


# Got this from an issue, lets you hover over an element
function Set-SeMousePosition {
    [CmdletBinding()]
    param ($Driver, $Element )
    $Action = [OpenQA.Selenium.Interactions.Actions]::new($Driver)
    $Action.MoveToElement($Element).Perform()
}

# This gets a list of all message after the 'new' bar on discord
function getNewMessages($messagesList) {
    $coords = (Find-SeElement -Driver $Driver -classname "divider-3_HH5L")[-1].Location.Y # The Y-coordinate of the 'new' bar
    $newMessages = @()
    for ($i = 0; $i -lt $messagesList.Length; $i += 1) {
        if ($messagesList[$i].Location.Y -gt $coords) {
            $newMessages += ($messagesList[$i])
        }
    }
    return $newMessages
}

while ($true) {
    $startTime = Get-Date -format "yyyy/MM/dd hh:mm:ss tt"
    $newDMLogEntries = @{}
    $notSent = @{}
    Get-Content $notSentFile | ConvertFrom-Csv | foreach { $notSent[$_.Key] = $_.Value }
    $sentIDs = Get-Content $sentFile
    $listWrappers = Find-SeElement -driver $Driver -classname "listItemWrapper-3X98Pc"
    if ($listWrappers.Length -gt 4) {
        $DMs = $listWrappers[1..$($listWrappers.Length - 4)]
    }
    else { $DMs = @() }
    # add this DM user to the list of people to pay attention to
    foreach ($DM in $DMs) {
        $attribute = (Find-SeElement -driver $DM -classname "wrapper-1BJsBx").GetAttribute("href") # This is the 'guildsnav___USERID' part of the menu buttons
        $id = $attribute.split('/')[-1]
        if (($null -eq $notSent ) -or (-not $notSent[$id])) {
            $newDMLogEntries += @{$id = $(Get-Date "1/1/20") }
        }
    }
    # add new user to list of users to monitor if we haven't already sent the message to them
    foreach ($newDMKey in $newDMLogEntries.Keys) {
        if ((-not $notSent.ContainsKey($newDMKey)) -and (-not ($sentIDs -contains $newDMKey))) {
            $notSent += @{ $newDMKey = $newDMLogEntries[$newDMKey] }
        }
    }

    $staticNotSent = $notSent.Clone()
    foreach ($id in $staticNotSent.Keys) {
        # only continue if its been over 2 minutes since this users messages were last read
        if ( ((Get-Date) - (Get-Date $notSent[$id])).TotalSeconds -lt $longSleep ) { Write-Host -Fore Yellow "Skipping $id"; continue }
        # $user = (Find-SeElement -driver $DM -classname "wrapper-1BJsBx").GetAttribute("aria-label") # This gets the users name
        Enter-SeUrl "https://discord.com/channels/@me/$id" -Driver $Driver
        $userName = (Find-SeElement -Driver $Driver -classname "username-1A8OIy")[0].GetAttribute("innerText")
        Write-Host -Fore Green "Checking $userName messages"
        $messagesList = Find-SeElement -Driver $Driver -classname "contents-2mQqc9" # These are all the messages in the chat

        $send = $false
        $result = getNewMessages $messagesList
        $keyWords = 0
        foreach ($message in $result) {
            if ((Find-SeElement -driver $message -tagname "div")[0].GetAttribute("innerText") -eq $keyWord) {
                # Checks each messages text to see if it matches $keyWord
                $send = $true
                $keyWords += 1
            }
        }
        $chatboxes = Find-SeElement -Driver $Driver -classname "slateTextArea-1Mkdgw" # The messaging input box
        if ($send) {
            $IP = "1.2.3.4"
            Write-Host -Fore Cyan "Sending IP $IP to $user"
            Add-Content -Path $sentFile -Value $id # Send $id to file so the script knows to ignore new messages from that user
            Send-SeKeys -Element $chatboxes[0] -Keys "$IP`n" # Send the IP
            #remove this id from notsent
            $notSent.Remove($id)
        }
        else {
            $notSent[$id] = $startTime 
        }
        $notSent.GetEnumerator() | select-object -Property Key, Value | Export-csv -NoTypeInformation $notSentFile
        # Set mouse to hover over message input box.  Prevents bugs from happening when mouse is already where it needs to be later
        Set-SeMousePosition -Driver $Driver -Element $chatboxes[0]
        if ($result.Length -gt $keyWords -or (!$send -and ($result.Length -eq 1))) {
            $clickee = $result[0]
            Set-SeMousePosition -Driver $Driver -Element $clickee # Set mouse to hover over the earliest new message
            $button = (Find-SeElement -Driver $Driver -classname "button-1ZiXG9")[2] # The three dots that show up on hover
            Send-SeClick -Element $button
            $clickee = (Find-SeElement -Driver $Driver -classname "label-22pbtT")[2] # The 'Mark Unread' button in the three dots menu
            Send-SeClick -Element $clickee
        }
        $send = $false
        Enter-SeUrl "https://discord.com/channels/@me" -Driver $Driver
    }
    Write-Host -Fore Cyan "Sleeping for $sleepTime seconds"
    Start-Sleep $sleepTime
}