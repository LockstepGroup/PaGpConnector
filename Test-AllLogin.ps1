[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$ApiServer = 'localhost',

    [Parameter(Mandatory = $false)]
    [string]$ApiPort = 10004
)

$DummyData = Import-Csv -Path $CsvPath
$UniqueUsers = $DummyData | Select-Object -Property Username -Unique

foreach ($user in $UniqueUsers) {
    $LoginMessage = "GlobalProtect gateway client configuration generated. User name: $($user.Username),"
    $Login = Invoke-RestMethod -Uri "http://$ApiServer`:$ApiPort/api/updaterule" -Method POST -Body $LoginMessage
}