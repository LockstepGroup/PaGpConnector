[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [int]$Count = 10,

    [Parameter(Mandatory = $False)]
    [string]$UsernamePrefix = 'vendor'
)

$Start = (Get-NetworkSummary 10.0.0.0/8).RangeStart | ConvertTo-DecimalIP
$Stop = (Get-NetworkSummary 10.0.0.0/8).RangeEnd | ConvertTo-DecimalIP



$ReturnArray = @()
for ($i = 1; $i -le $Count; $i++) {
    $Username = $UsernamePrefix + "$i"
    $NumberOfIpsToGenerate = Get-Random -Minimum 1 -Maximum 10
    for ($n = 1; $n -le $NumberOfIpsToGenerate; $n++) {
        $entry = "" | Select-Object Username, IpAddress
        $entry.Username = $UserName
        $entry.IpAddress = Get-Random -Minimum $Start -Maximum $Stop | ConvertTo-DottedDecimalIP
        $ReturnArray += $entry
    }
}

$ReturnArray