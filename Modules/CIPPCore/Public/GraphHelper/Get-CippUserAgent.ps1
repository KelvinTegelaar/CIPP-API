function Get-CippUserAgent {
    <#
    .SYNOPSIS
        Builds the User-Agent string for outbound M365 API requests.
    .DESCRIPTION
        Returns 'CIPP/<version>' optionally suffixed with semicolon-delimited 'key:value' context segments
        set via Set-CippUserAgentContext, e.g. 'CIPP/8.2.0 (user:john@msp.com)' or
        'CIPP/8.2.0 (scheduled-task:<taskid>; user:john@msp.com)'.
        This allows MDR/security teams to attribute CIPP activity in M365 audit logs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # SharePoint Online prioritises traffic decorated as ISV.
        [switch]$SharePoint
    )

    $Version = [System.Environment]::GetEnvironmentVariable('CippVersion') ?? [System.Environment]::GetEnvironmentVariable('APP_VERSION') ?? '1.0'
    $Context = $script:CippUserAgentContextStorage.Value
    $Product = if ($SharePoint) { 'ISV|CIPP/{0}' -f $Version } else { 'CIPP/{0}' -f $Version }

    if ($Context.Source) {
        $Segments = [System.Collections.Generic.List[string]]::new()
        if ($Context.Source -in @('user', 'api')) {
            # Identity belongs to the source itself, e.g. user:john@msp.com or api:<appid>
            $Segments.Add($Context.Identity ? ('{0}:{1}' -f $Context.Source, $Context.Identity) : $Context.Source)
        } else {
            $Id = if ($Context.TaskId) { $Context.TaskId } else { $Context.TemplateId }
            $Segments.Add($Id ? ('{0}:{1}' -f $Context.Source, $Id) : $Context.Source)
            if ($Context.Identity) {
                $Segments.Add('user:{0}' -f $Context.Identity)
            }
        }
        return ('{0} ({1})' -f $Product, ($Segments -join '; '))
    }
    return $Product
}
