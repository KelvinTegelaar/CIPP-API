function Invoke-ListCommunityRepos {
    <#
    .SYNOPSIS
        List community repositories in Table Storage
    .DESCRIPTION
        This function lists community repositories in Table Storage
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName CommunityRepos
    $Repos = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
        [pscustomobject]@{
            Id              = $_.RowKey
            Name            = $_.Name
            Description     = $_.Description
            URL             = $_.URL
            FullName        = $_.FullName
            Owner           = $_.Owner
            Visibility      = $_.Visibility
            WriteAccess     = $_.WriteAccess
            RepoPermissions = $_.Permissions | ConvertFrom-Json
        }
    }

    $Body = @{
        Results = @($Repos)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
