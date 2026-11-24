function Invoke-ListAppTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.Read
    .DESCRIPTION
        Lists the saved application deployment templates, each with its display name, description and the applications it bundles. These are CIPP templates, not a tenant's deployed apps.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'AppTemplate'"
    $RawTemplates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    $PackageSizes = @{}
    try {
        foreach ($File in Get-CIPPAppPackageFile -ErrorAction SilentlyContinue) {
            if ($File.Name.EndsWith('/IntunePackage.intunewin')) { $PackageSizes[$File.PackageId] = $File.Size }
        }
    } catch {
        Write-Information "Could not read app package sizes: $($_.Exception.Message)"
    }

    $Templates = foreach ($Template in $RawTemplates) {
        try {
            $JSONData = $Template.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
            $Apps = if ($JSONData.Apps) { @($JSONData.Apps) } else { @() }
            $PackageIds = [regex]::Matches([string]$Template.JSON, 'packageId\\?"\s*:\s*\\?"([0-9a-fA-F-]{36})').ForEach({ $_.Groups[1].Value })
            [PSCustomObject]@{
                displayName        = $JSONData.Displayname
                description        = $JSONData.Description
                appCount           = $Apps.Count
                appTypes           = @($Apps | ForEach-Object { $_.appType } | Sort-Object -Unique)
                appNames           = @($Apps | ForEach-Object { $_.appName })
                packageSizeInBytes = if ($PackageIds.Count) { [int64]($PackageIds.ForEach({ $PackageSizes[$_] }) | Measure-Object -Sum).Sum } else { $null }
                Apps               = $Apps
                GUID               = $Template.RowKey
            }
        } catch {}
    }

    $Templates = @($Templates | Sort-Object -Property displayName)

    if ($Request.Query.ID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.Query.ID
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ConvertTo-Json -Depth 100 -InputObject @($Templates)
    })
}
