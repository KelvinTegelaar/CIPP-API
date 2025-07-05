using namespace System.Net

function Invoke-ListGroupTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    try {
        #List new policies
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'GroupTemplate'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $data = $_.JSON | ConvertFrom-Json
            [PSCustomObject]@{
                displayName     = $data.displayName
                description     = $data.description
                groupType       = $data.groupType
                membershipRules = $data.membershipRules
                allowExternal   = $data.allowExternal
                username        = $data.username
                GUID            = $_.RowKey
            }
        } | Sort-Object -Property displayName

        if ($Request.Query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.Query.id }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Templates = $_.Exception.Message
    }


    return @{
        StatusCode = $StatusCode
        Body       = @($Templates)
    }
}
