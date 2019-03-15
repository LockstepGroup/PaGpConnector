# PaGpConnector

This is a POC designed to show off the flexibility of the Palo Alto API. It demonstrates how you would get a list of devices a GlobalProtect user should have access to from a third party and then create Security Policies based on that information. Included in this repo is a script to simulate the third party API. The overall flow looks like this.


[![workflow](https://github.com/LockstepGroup/PaGpConnector/raw/master/PaGpConnector.svg?sanitize=true)]

## Prerequisites

* Powershell Version 5.1+ or Core
* PanOS 8.0+
* [PowerAlto](https://www.poweralto.com) PowerShell Module
* [CorkScrew](https://github.com/LockstepGroup/CorkScrew) PowerShell Module
* [Universal Dashboard](https://github.com/ironmansoftware/universal-dashboard) PowerShell Module

## Setup

### Dummy Data API (GetDevice.ps1)

1. Install the PowerShell Modules listed above.
2. Clone this repo to your server, if you've already installed CorkScrew from above you can use the following.
    ```powershell
    Get-GithubRepo -Owner LockstepGroup -Repository PaGpConnector -TargetPath "c:\my\path"
    ```
3. Use New-DummyData to create a csv file full of dummy users and devices.
    ```powershell
    New-DummyData.ps1 -Count 10 -UsernamePrefix 'user' | Export-Csv -Path "./DummyData.csv"
    ```
4. Now you should be able to startup the API server to return these devices.  Make sure you used `DummyData.csv` as your filename in the last step, it's hardcoded into this script.
    ```powershell
    ./GetDevice.ps1

    # test the api
    Invoke-RestMethod -Uri 'http://localhost:10005/api/getdevice/user1'
    ```

### Update Rule Api (UpdateRule.ps1)

1. Obtain an API key from your Palo Alto
    ```powershell
    Import-Module PowerAlto
    Get-PaDevice -DeviceAddress 'pa.example.com' -Credential (Get-Credential) # you'll be prompted for your PA Credentials
    $PaDeviceObject.ApiKey # outputs your api key to the screen
    ```
2. First we have to setup a config file in json format as follows.
    ```powershell
    $config = @{}

    # Pa setup
    $config.PaDevice = '1.1.1.1' # MGT ip of your PA
    $config.SourceZone = 'globalprotect' # zone your globalprotect clients are in
    $config.DestinationZone = 'lan' # zone to allow globalprotect clients to get to
    $config.Commit = $true # enables autocommiting of changes made by this api

    # Credentials
    $config.AesKey = New-EncryptionKey # creates an AES key to encrypt credentials with
    $config.ApiKey = New-EncryptedString -PlainTextString 'myapikey' -AesKey $config.AesKey # apikey for accessing PA

    # Logging Setup
    $config.LogThreshold = 5 # 1-6, higher is more verbose, logs are stored to updaterule.log in script dir

    # Optional setup for LogDna if you have an account
    $config.LogDnaApiKey = New-EncryptedString -PlainTextString 'myapikey' -AesKey $config.AesKey # apikey for LogDna
    $config.LogDnaEnvironment = 'Test Lab' # arbitrary identifier for these logs in LogDna
    $config.SyslogApplication = 'PaGpConnector' # arbitrary application field fir LogDna

    # Export to config.json in the same dir you saved the repo to
    $config | ConvertTo-Json | Out-File ./config.json
    ```
3. Start the API
    ```powershell
    ./UpdateRule.ps1
    ```

### Palo Alto Setup

#### Setup an HTTP Server Profile

1. Login to your PA and navigate to Device > Server Profiles > HTTP
2. Click Add
3. Click Add on the Servers tab in the HTTP Server Profile dialog and configure as follows, this is for your PowerShell WebServer

    | Setting | Value |
    |---|---|
    | Name | PowerShell WebServer |
    | Address | fqdn of your PowerShell WebServer |
    | Protocol | http (unless you got fancy) |
    | Port | 10004 |
    | HTTP Method | POST |

4. On the Payload Format tab click System and configure as follows

    | Setting | Value |
    |---|---|
    | Name | updaterule |
    | URI Format | /api/updaterule |
    | Payload | $opaque |

#### Enable System Log Forwarding

1. Login to your PA and navigate to Device > Log Settings
2. Click Add udner the System "pod" and configure as follows.

    | Setting | Value |
    |---|---|
    | Name | PowerShell WebServer |
    | Filter | ( subtype eq globalprotect ) and (description contains 'GlobalProtect gateway client configuration') |
    | HTTP | Click Add, and select your HTTP Profile |

3. Commit

# That's It

That's all, now you should be able to login with a valid GlobalProtect user that you've created dummy data for and watch Security Policies magically appear. Also included is a script to simulate logins from all the users in the DummyData.csv file. This doesn't actually login to globalprotect, but just simulates logs forwarded from the PA to the API as if it did. Usage:

```powershell
./Test-AllLogin.ps1 -CsvPath ./DummyData.csv
```