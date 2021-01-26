$keyWords = @("z", "pizza") # an array of keywords to respond to. The keyword will be matched to the whole line of the message, but not a substring.
$sleepTime = 2 # time in seconds to sleep before checking messages again
$longSleep = 20
$browser = "Chrome" # other options are "Firefox" and "Edge" but only Chrome has been tested by the developers
$maximized = $false # set to True if you want the browser to start maximized

# creating working files/directories for keeping track of things to check and things that have been sent
$sentFile = "$PSScriptRoot\WorkingDirectory\sentFile.txt"
if (-not (Test-Path $sentFile) ) { $null = New-Item -ItemType File -Path $sentFile -Force }
$notSentFile = "$PSScriptRoot\WorkingDirectory\notSentFile.txt"
if (-not (Test-Path $notSentFile) ) { $null = New-Item -ItemType File -Path $notSentFile -Force }

# create the web driver and open discord to the login page
if ($null -eq $Driver) {
    $arguments = @()
    if ($maximized) { $arguments += 'start-maximized' }
    try {
        $Driver = &"Start-Se$browser" -Arguments $arguments -Quiet
    }
    catch {
        Write-Host -ForegroundColor Red "There was a problem starting the Selenium Web Driver for $browser. Please check the README file for this project for details on installing it."
        $_.Exception.message
        exit
    }
    Enter-SeUrl "https://www.discord.com/login" -Driver $Driver
}

# This gets a list of all messages after the red 'new' bar on discord Direct Messages
function Get-NewMessages($messagesList) {
    $coords = (Find-SeElement -Driver $Driver -classname "unreadPillCap-3_K2q2").Location.Y # The Y-coordinate of the 'new' bar
    $newMessages = @()
    foreach ($message in $messagesList) {
        if (($null -ne $coords) -and ($message.Location.Y -gt $coords)) {
            $newMessages += $message
        }
    }
    return $newMessages
}

function MatchKeyword ($message) {
    foreach ($keyWord in $keyWords) {
        if ($message -eq $keyWord) { return $true }
    }
    return $false
}

# an infinite loop to check messages and then respond
while ($true) {
    # notSent is a hashtable of anyone that has sent us a DM that we haven't sent a botMessage to yet.
    # notSent is read from a file at the beginning of the while loop and written back out to a the file at the end of the while loop
    $notSent = @{}
    Get-Content $notSentFile | ConvertFrom-Csv | ForEach-Object { $notSent[$_.Key] = $_.Value }
    # the sentFile is a list of discord user IDs that we have already sent a botMessage to (so they can be ignored by this bot)
    $sentIDs = Get-Content $sentFile
    # a new DM shows up in a "listWrapper" html element, there are 4 static listwrappers, if we see more than these 4, we know we represent a DM
    $listWrappers = Find-SeElement -driver $Driver -classname "listItemWrapper-3X98Pc"
    if ($listWrappers.Length -gt 4) {
        $DMs = $listWrappers[1..$($listWrappers.Length - 4)] # we ignore the static listWrappers (the first one and the last 3)
    }
    else { $DMs = @() }

    foreach ($DM in $DMs) {
        $attribute = (Find-SeElement -driver $DM -classname "wrapper-1BJsBx").GetAttribute("href") # This is the 'guildsnav___USERID' part of the menu buttons
        $id = $attribute.split('/')[-1]
        # skip this user if we have already responded
        if ($sentIDs -contains $id) { continue }
        # add user to the notSent list if they are not already there
        if ( -not $notSent.ContainsKey($id) ) {
            $notSent += @{ $id = $(Get-Date "1/1/20") }
        }
        # only continue if its been over $longSleep seconds since this users messages were last read
        if ( ((Get-Date) - (Get-Date $notSent[$id])).TotalSeconds -lt $longSleep ) { Write-Host -Fore Yellow "Skipping $id"; continue }
        Enter-SeUrl "https://discord.com/channels/@me/$id" -Driver $Driver
        $userName = (Find-SeElement -Driver $Driver -classname "title-29uC1r").GetAttribute("innerText")
        Write-Host -Fore Green "Checking $userName messages $id"
        $messagesList = Find-SeElement -Driver $Driver -classname "messageContent-2qWWxC" # These are all the messages in the chat
        $notSent[$id] = Get-Date -format "yyyy/MM/dd hh:mm:ss tt"

        $results = Get-NewMessages $messagesList
        if ($results | where-object { MatchKeyword $_.getAttribute("innerText") }) {
            # Send the message
            $chatboxes = Find-SeElement -Driver $Driver -classname "slateTextArea-1Mkdgw" # The messaging input box
            $message = Get-BotMessage $id $userName
            if ($message) {
                Add-Content -Path $sentFile -Value $id # Send $id to file so the script knows to ignore new messages from that user
                Write-Host -Fore Cyan "Sending message to $userName"
                foreach ($line in $message.split("`n")) {
                    Send-SeKeys -Element $chatboxes[-1] -Keys "$line" 
                    Send-SeKeys -Element $chatboxes[-1] -Keys "{{shift}}{{ENTER}}"
                }
                Send-SeKeys -Element $chatboxes[-1] -Keys "{{ENTER}}"
                Start-Sleep 1
                #remove this id from notsent
                $notSent.Remove($id)
            }
            else { Write-Host -ForegroundColor Red "No message Returned, no message sent to $id $userName" }
        }        
        foreach ($result in $results) {
            if (-not (MatchKeyword $result.getAttribute("innerText"))) {
                # Mark message as unread, click the message so the elipsis button shows up
                $result | Invoke-SeClick
                (Find-SeElement -Driver $Driver -classname "button-1ZiXG9")[2] | Invoke-SeClick -Driver $Driver -JavaScriptClick # The three dots that show up on hover
                (Find-SeElement -Driver $Driver -classname "label-22pbtT")[2]  | Invoke-SeClick -Driver $Driver -JavaScriptClick # The 'Mark Unread' button in the three dots menu
                break   
            }
        }
        Enter-SeUrl "https://discord.com/channels/@me" -Driver $Driver

    }
    $notSent.GetEnumerator() | select-object -Property Key, Value | Export-csv -NoTypeInformation $notSentFile

    Write-Host -Fore Cyan "Sleeping for $sleepTime seconds"
    Start-Sleep $sleepTime 
}