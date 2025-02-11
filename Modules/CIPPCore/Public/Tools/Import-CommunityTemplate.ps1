function Import-CommunityTemplate {
    <#

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        [switch]$Force
    )

    $Table = Get-CippTable -TableName 'templates'
    $Filter = "PartitionKey eq '$Type'"

    $CippTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $GUID = $_.RowKey
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
        $data
    }

    $Contents = $Template.content
    Write-Host ($Contents)
}
