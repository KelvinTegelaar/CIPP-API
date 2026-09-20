function Get-HuduBitLockerKeySlot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$KeyMetadata
    )

    $Counters = @{}
    $Slots = foreach ($Key in @($KeyMetadata | Sort-Object id -Unique)) {
        $Group = switch ([string]$Key.volumeType) {
            { $_ -in '1', 'operatingSystemVolume' } { 'OS Drive'; break }
            { $_ -in '2', 'fixedDataVolume' } { 'Fixed Data Drive'; break }
            { $_ -in '3', 'removableDataVolume' } { 'Removable Data Drive'; break }
            default { 'Unknown Drive' }
        }
        $Counters[$Group] = 1 + [int]$Counters[$Group]
        $Label = "BitLocker $Group $($Counters[$Group])"
        $Prefix = $Label.Replace(' ', '_').ToLowerInvariant()
        [PSCustomObject]@{
            KeyId         = [string]$Key.id
            IdLabel       = "$Label Key ID"
            PasswordLabel = "$Label Recovery Key"
            IdField       = "${Prefix}_key_id"
            PasswordField = "${Prefix}_recovery_key"
        }
    }

    return $Slots
}
