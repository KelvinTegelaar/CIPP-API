using namespace System.Net

function Invoke-ListCAtemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    Write-Host $Request.query.id
    #Migrating old policies whenever you do a list
    $Table = Get-CippTable -tablename 'templates'
    $Imported = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings'"
    if ($Imported.CATemplate -ne $true) {
        $Templates = Get-ChildItem 'Config\*.CATemplate.json' | ForEach-Object {
            $Entity = @{
                JSON         = "$(Get-Content $_)"
                RowKey       = "$($_.name)"
                PartitionKey = 'CATemplate'
                GUID         = "$($_.name)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            CATemplate   = $true
            RowKey       = 'CATemplate'
            PartitionKey = 'settings'
        } -Force
    }
    try {
        #List new policies
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'CATemplate'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $data = $_.JSON | ConvertFrom-Json -Depth 100
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
            $data
        } | Sort-Object -Property displayName

        if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }
        $Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Templates = "Failed to list CA templates. Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = $Templates
    }
}
