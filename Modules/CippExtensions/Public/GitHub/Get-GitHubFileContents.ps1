function Get-GitHubFileContents {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        $Url
    )

    process {
        [uri]$Uri = $Url
        $Path = $Uri.PathAndQuery.TrimStart('/')
        $File = Invoke-GitHubApiRequest -Path "$Path" -Method GET

        return [PSCustomObject]@{
            name    = $File.name
            path    = $File.path
            content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($File.content))
            sha     = $File.sha
            size    = $File.size
        }
    }
}
