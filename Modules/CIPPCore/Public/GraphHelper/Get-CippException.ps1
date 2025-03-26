function Get-CippException {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        $Exception
    )

    [PSCustomObject]@{
        Message         = $Exception.Exception.Message
        NormalizedError = Get-NormalizedError -message $Exception.Exception.Message
        Position        = $Exception.InvocationInfo.PositionMessage
        ScriptName      = $Exception.InvocationInfo.ScriptName
        LineNumber      = $Exception.InvocationInfo.ScriptLineNumber
        Category        = $Exception.CategoryInfo.ToString()
    }
}
