function Get-CippException {
    Param(
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
