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


    Write-Host $Request.query.id

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'GroupTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json

        # Normalize groupType to camelCase for consistent frontend handling
        $normalizedGroupType = switch -Wildcard ($data.groupType.ToLower()) {
            '*dynamicdistribution*' { 'dynamicDistribution'; break }
            '*dynamic*' { 'dynamic'; break }
            '*azurerole*' { 'azureRole'; break }
            '*unified*' { 'm365'; break }
            '*microsoft*' { 'm365'; break }
            '*m365*' { 'm365'; break }
            '*generic*' { 'generic'; break }
            '*security*' { 'security'; break }
            '*distribution*' { 'distribution'; break }
            '*mail*' { 'distribution'; break }
            default { $data.groupType }
        }

        [PSCustomObject]@{
            displayName     = $data.displayName
            description     = $data.description
            groupType       = $normalizedGroupType
            membershipRules = $data.membershipRules
            allowExternal   = $data.allowExternal
            username        = $data.username
            GUID            = $_.RowKey
        }
    } | Sort-Object -Property displayName

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
