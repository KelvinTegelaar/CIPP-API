function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $CIPPVersion = $request.query.LocalVersion
    $CleanupStale = $request.query.CleanupStale -eq 'true'

    # If cleanup requested, remove stale version entries first
    if ($CleanupStale) {
        try {
            $VersionTable = Get-CippTable -tablename 'Version'
            $AllVersions = Get-CIPPAzDataTableEntity @VersionTable -Filter "PartitionKey eq 'Version'"
            
            foreach ($ver in $AllVersions) {
                # Remove entries with very old versions (before v7.0.0) or invalid versions
                if ($ver.Version) {
                    try {
                        $semVer = [semver]$ver.Version
                        if ($semVer.Major -lt 7) {
                            Write-Information "Removing stale version entry: $($ver.RowKey) = $($ver.Version)"
                            Remove-CIPPAzDataTableEntity @VersionTable -Entity $ver
                        }
                    } catch {
                        # Invalid semver - remove it
                        Write-Information "Removing invalid version entry: $($ver.RowKey) = $($ver.Version)"
                        Remove-CIPPAzDataTableEntity @VersionTable -Entity $ver
                    }
                }
            }
        } catch {
            Write-Warning "Failed to cleanup stale versions: $($_.Exception.Message)"
        }
    }

    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Version
        })
}
