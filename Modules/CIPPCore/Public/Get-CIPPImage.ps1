function Get-CIPPImage {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Retrieves one or more images from the Images table.
    .DESCRIPTION
        Pass a single -Id to receive the image object (or $null if missing).
        Pass multiple -Id values to receive a hashtable of id -> image object
        (missing ids are omitted).

        Image payloads are often larger than a single table property/entity, so
        Add-CIPPAzDataTableEntity may store them across the original RowKey and
        `{RowKey}-partN` rows. Filters must include those part rows or
        Get-CIPPAzDataTableEntity cannot reassemble `data`.

        Those rows are matched by RowKey range, not by OriginalEntityId. The Edm
        type of that property is decided by whatever wrote the row, so naming it
        in a filter means guessing: comparing it to both a string and a guid
        literal is accepted by Azurite and rejected outright by the real table
        service, and a rejected query looks identical here to a missing image -
        which is how an uploaded logo could sit visibly in the table and still
        read back as "no logo". A RowKey range needs no type at all.
    .PARAMETER PartitionKey
        Image kind / purpose (e.g. logo, brandingCover). Required.
    .PARAMETER Id
        One or more image RowKey GUIDs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PartitionKey,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Id
    )

    $Ids = @($Id | Where-Object { $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_".Trim() } | Select-Object -Unique)
    $ReturnScalar = $Ids.Count -eq 1

    if ($Ids.Count -eq 0) {
        if ($ReturnScalar -or @($Id).Count -le 1) { return $null }
        return @{}
    }

    $Table = Get-CIPPTable -TableName 'Images'
    $IdClauses = foreach ($ImageId in $Ids) {
        $SafeId = $ImageId.Replace("'", "''")
        "(RowKey ge '$SafeId' and RowKey lt '$SafeId~')"
    }
    $Filter = "PartitionKey eq '$($PartitionKey.Replace("'","''"))' and ($($IdClauses -join ' or '))"

    $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    $Result = @{}

    foreach ($ImageId in $Ids) {
        $Entity = $Entities | Where-Object { $_.RowKey -eq $ImageId } | Select-Object -First 1
        if ($Entity -and $Entity.data) {
            $Result[$ImageId] = @{
                id           = $ImageId
                partitionKey = $PartitionKey
                data         = $Entity.data
                contentType  = $Entity.contentType
                created      = $Entity.created
            }
        }
    }

    if ($ReturnScalar) {
        if ($Result.ContainsKey($Ids[0])) {
            return $Result[$Ids[0]]
        }
        return $null
    }

    return $Result
}
