function Add-CIPPQuarantineMessageProperties {
    <#
    .SYNOPSIS
        Adds CIPP computed properties to a quarantine message object.
    .DESCRIPTION
        Enriches Get-QuarantineMessage output with Tenant, CustomerId and NetworkMessageId.
        NetworkMessageId is the first half of the quarantine Identity ({NetworkMessageId}\{RecipientGuid})
        and is used by the frontend to build Microsoft Defender email entity deep links.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Message,
        [Parameter(Mandatory = $true)][string]$Tenant,
        [string]$CustomerId
    )
    $Message | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
    if ($CustomerId) {
        $Message | Add-Member -NotePropertyName 'CustomerId' -NotePropertyValue $CustomerId -Force
    }
    $Message | Add-Member -NotePropertyName 'NetworkMessageId' -NotePropertyValue ([string]($Message.Identity -split '\\')[0]) -Force
}
