function Convert-AzureAdObjectIdToSid {
    <#
    .SYNOPSIS
        Converts an Azure AD / Entra ID Object ID (GUID) to its Windows SID representation.
    .DESCRIPTION
        Parses the 16-byte GUID of an Azure AD Object ID and re-interprets the bytes as four
        unsigned 32-bit integers, producing a SID in the form S-1-12-1-{b0}-{b1}-{b2}-{b3}.
        This is the format used by Microsoft when translating cloud identities to on-premises
        or hybrid Windows security contexts.
    .PARAMETER ObjectID
        The Azure AD / Entra ID Object ID (GUID) to convert. Must be a valid GUID string.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Convert-AzureAdObjectIdToSid -ObjectID '00000000-0000-0000-0000-000000000001'
        Returns the Windows SID corresponding to the specified Entra ID Object ID.
    #>
    param (
        [parameter(Mandatory = $true)][string]$ObjectID
    )

    $Bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $Array = New-Object 'UInt32[]' 4

    [Buffer]::BlockCopy($Bytes, 0, $Array, 0, 16)
    $Sid = "S-1-12-1-$Array".Replace(' ', '-')
    return $Sid
}
