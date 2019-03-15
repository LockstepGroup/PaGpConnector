[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$ApiServer = 'localhost',

    [Parameter(Mandatory = $false)]
    [string]$ApiPort = 10004,

    [Parameter(Mandatory = $false)]
    [ValidateSet('login', 'logout')]
    [string]$Action = 'login'
)

$DummyData = Import-Csv -Path $CsvPath
$UniqueUsers = $DummyData | Select-Object -Property Username -Unique

foreach ($user in $UniqueUsers) {
    switch ($Action) {
        'login' {
            $LoginMessage = "GlobalProtect gateway client configuration generated. User name: $($user.Username),"
            break
        }
        'logout' {
            $LoginMessage = "GlobalProtect gateway client configuration released. User name: $($user.Username),"
            break
        }
    }

    $Test = Invoke-RestMethod -Uri "http://$ApiServer`:$ApiPort/api/updaterule" -Method POST -Body $LoginMessage
}