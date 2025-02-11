function Get-GitHubFileContents {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $FullName,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $Path,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        $Branch
    )

    process {
        $Path = "repos/$($FullName)/contents/$($Path)?ref=$($Branch)"
        #Write-Information $Path
        $File = Invoke-GitHubApiRequest -Path $Path -Method GET

        return [PSCustomObject]@{
            name    = $File.name
            path    = $File.path
            content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($File.content))
            sha     = $File.sha
            size    = $File.size
        }
    }
}
