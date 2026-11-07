<#
.SYNOPSIS
Minifier-Agnostic System Prompt Debloater, Sandbox Patcher & Ripgrep Healer for Roo Code (patch-roocode.ps1)

.DESCRIPTION
Deterministically patches Roo Code's compiled bundle (dist/extension.js) using content-anchored
regular expressions that survive esbuild/webpack identifier renaming across extension updates:
- Auto-heals missing rg.exe (ripgrep) binaries across VS Code commit-hash resources/app directories (fixes Turn-1 'API Request...' hangs)
- Strips ~1,560 tokens of repetitive legacy XML-era boilerplate (CAPABILITIES, OBJECTIVE, Tool Use Guidelines)
- Eliminates the duplicate 120-word environment_details paragraph & '/test/path' bug in SYSTEM INFORMATION
- Compresses the 750-word RULES block into 4 high-density execution invariants while strictly preserving the adjacent inlined execa ($xu) module
- Optionally expands built-in Architect mode's fileRegex from \.md$ to allow .txt and .*ignore files

.PARAMETER Restore
Restores dist/extension.js from the clean dist/extension.js.bak backup.

.PARAMETER SkipArchitectRegex
Skips expanding built-in Architect mode's fileRegex beyond \.md$.

.PARAMETER SkipRipgrepFix
Skips auto-provisioning rg.exe into VS Code resources/app directories.

.PARAMETER ExtensionPath
Optional explicit path to dist/extension.js (auto-detected across ~/.vscode, ~/.vscode-insiders, and ~/.cursor by default).
#>
[CmdletBinding()]
param(
    [switch]$Restore,
    [switch]$SkipArchitectRegex,
    [switch]$SkipRipgrepFix,
    [string]$ExtensionPath
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 1. Auto-Heal VS Code Ripgrep (rg.exe) across commit-hash resources/app directories
if (-not $SkipRipgrepFix -and -not $Restore) {
    $VsCodeBases = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders",
        "$env:LOCALAPPDATA\Programs\Cursor",
        "C:\Program Files\Microsoft VS Code"
    ) | Where-Object { Test-Path $_ }

    foreach ($VsBase in $VsCodeBases) {
        $RgBin = Get-ChildItem -Path $VsBase -Filter "rg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($RgBin) {
            $AppRoots = Get-ChildItem -Path $VsBase -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.FullName -match '\\resources\\app$'
            }
            foreach ($AppRoot in $AppRoots) {
                $CandidateDirs = @(
                    (Join-Path $AppRoot.FullName "node_modules\@vscode\ripgrep\bin"),
                    (Join-Path $AppRoot.FullName "node_modules\vscode-ripgrep\bin"),
                    (Join-Path $AppRoot.FullName "node_modules.asar.unpacked\@vscode\ripgrep\bin"),
                    (Join-Path $AppRoot.FullName "node_modules.asar.unpacked\vscode-ripgrep\bin")
                )
                foreach ($Dir in $CandidateDirs) {
                    $TargetRg = Join-Path $Dir "rg.exe"
                    if (-not (Test-Path $TargetRg)) {
                        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                        Copy-Item -Path $RgBin.FullName -Destination $TargetRg -Force
                        Write-Host "  [+] Provisioned rg.exe -> $TargetRg" -ForegroundColor Green
                    }
                }
            }
        }
    }
}

# 2. Auto-discover latest installed rooveterinaryinc.roo-cline dist/extension.js
if (-not $ExtensionPath) {
    $SearchRoots = @(
        (Join-Path $env:USERPROFILE ".vscode\extensions"),
        (Join-Path $env:USERPROFILE ".vscode-insiders\extensions"),
        (Join-Path $env:USERPROFILE ".cursor\extensions")
    ) | Where-Object { Test-Path $_ }

    $ExtFile = foreach ($Root in $SearchRoots) {
        Get-ChildItem -Path $Root -Filter "rooveterinaryinc.roo-cline*" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "dist\extension.js" } |
            Where-Object { Test-Path $_ } |
            Get-Item
    }
    $ExtFile = $ExtFile | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $ExtFile) {
        throw "Could not locate rooveterinaryinc.roo-cline dist/extension.js in standard VS Code extension directories."
    }
    $ExtensionPath = $ExtFile.FullName
}

$BackupPath = "$ExtensionPath.bak"
Write-Host "Target Bundle : $ExtensionPath" -ForegroundColor Cyan

# 3. Handle -Restore flag
if ($Restore) {
    if (-not (Test-Path $BackupPath)) {
        throw "No backup file found at $BackupPath"
    }
    Copy-Item -Path $BackupPath -Destination $ExtensionPath -Force
    Write-Host "[RESTORED] Reverted $ExtensionPath from clean backup." -ForegroundColor Green
    exit 0
}

# 4. Create clean backup if not already present (always read from .bak for 100% idempotency)
if (-not (Test-Path $BackupPath)) {
    Copy-Item -Path $ExtensionPath -Destination $BackupPath -Force
    Write-Host "[BACKUP] Created clean backup at $BackupPath" -ForegroundColor Green
} else {
    Write-Host "[BACKUP] Reading from existing clean backup ($BackupPath)" -ForegroundColor DarkGray
}

$RawJs = [System.IO.File]::ReadAllText($BackupPath, [System.Text.Encoding]::UTF8)
$OriginalLength = $RawJs.Length

# ==============================================================================
# CONTENT-ANCHORED REGEX PATCHES (Survives esbuild/webpack minifier renames)
# ==============================================================================

# Patch A: Empty out Tool Use Guidelines (`# Tool Use Guidelines\n\n1. Assess what information...`)
$PatternGuidelines = 'function (?<fn>[A-Za-z0-9_$]+)\(\)\{return`# Tool Use Guidelines[\s\S]*?accuracy of your work\.`\}'
$MatchGuidelines = [regex]::Match($RawJs, $PatternGuidelines)
if ($MatchGuidelines.Success) {
    $FnGuidelines = $MatchGuidelines.Groups['fn'].Value
    $RawJs = [regex]::Replace($RawJs, $PatternGuidelines, "function $FnGuidelines(){return`"`"}")
    Write-Host "  [+] Stripped Tool Use Guidelines ($FnGuidelines)" -ForegroundColor Green
} else {
    Write-Warning "  [!] Pattern not matched: Tool Use Guidelines"
}

# Patch B: Empty out CAPABILITIES (`====\n\nCAPABILITIES...` including nested MCP template literal `:""}`}`)
$PatternCaps = 'function (?<fn>[A-Za-z0-9_$]+)\((?<args>[^)]*)\)\{return`====\s+CAPABILITIES[\s\S]*?:""\}`\}'
$MatchCaps = [regex]::Match($RawJs, $PatternCaps)
if ($MatchCaps.Success) {
    $FnCaps = $MatchCaps.Groups['fn'].Value
    $ArgsCaps = $MatchCaps.Groups['args'].Value
    $RawJs = [regex]::Replace($RawJs, $PatternCaps, "function $FnCaps($ArgsCaps){return`"`"}")
    Write-Host "  [+] Stripped CAPABILITIES section ($FnCaps)" -ForegroundColor Green
} else {
    Write-Warning "  [!] Pattern not matched: CAPABILITIES"
}

# Patch C: Empty out OBJECTIVE (`====\n\nOBJECTIVE...`)
$PatternObj = 'function (?<fn>[A-Za-z0-9_$]+)\(\)\{return`====\s+OBJECTIVE[\s\S]*?further assistance\.`\}'
$MatchObj = [regex]::Match($RawJs, $PatternObj)
if ($MatchObj.Success) {
    $FnObj = $MatchObj.Groups['fn'].Value
    $RawJs = [regex]::Replace($RawJs, $PatternObj, "function $FnObj(){return`"`"}")
    Write-Host "  [+] Stripped OBJECTIVE section ($FnObj)" -ForegroundColor Green
} else {
    Write-Warning "  [!] Pattern not matched: OBJECTIVE"
}

# Patch D: Compress SYSTEM INFORMATION & Fix '/test/path' Duplicate Paragraph Bug
$PatternSysInfo = 'function (?<fn>[A-Za-z0-9_$]+)\((?<args>[^)]*)\)\{let [A-Za-z0-9_$]+;try\{[\s\S]*?`====\s+SYSTEM INFORMATION[\s\S]*?Current Workspace Directory: \$\{(?<cwd>[^}]+)\}[\s\S]*?like the Desktop\.`\}'
$MatchSysInfo = [regex]::Match($RawJs, $PatternSysInfo)
if ($MatchSysInfo.Success) {
    $FnSys = $MatchSysInfo.Groups['fn'].Value
    $ArgsSys = $MatchSysInfo.Groups['args'].Value
    $CwdExpr = $MatchSysInfo.Groups['cwd'].Value
    $ReplacementSys = "function $FnSys($ArgsSys){return``====\n\nSYSTEM INFORMATION\n\nOS: `$(process.platform) | Shell: pwsh.exe (PowerShell 7) | Workspace: `${$CwdExpr}``}"
    $RawJs = [regex]::Replace($RawJs, $PatternSysInfo, $ReplacementSys)
    Write-Host "  [+] Compressed SYSTEM INFORMATION & removed '/test/path' duplicate essay ($FnSys)" -ForegroundColor Green
} else {
    Write-Warning "  [!] Pattern not matched: SYSTEM INFORMATION"
}

# Patch E: Compress RULES (750 words -> 4 high-density invariants)
# Strictly anchored to the closing `isStealthModel` interpolation of getRulesSection so the adjacent inlined execa ($xu) bundle is never touched!
$PatternRules = 'function (?<fn>[A-Za-z0-9_$]+)\((?<cwd>[A-Za-z0-9_$]+)(?<restArgs>,[^)]*)?\)\{let [^`]*`====\s+RULES[\s\S]*?\$\{[A-Za-z0-9_$]+\?\.isStealthModel\?[A-Za-z0-9_$]+\(\):""\}`\}'
$MatchRules = [regex]::Match($RawJs, $PatternRules)
if ($MatchRules.Success) {
    $FnRules = $MatchRules.Groups['fn'].Value
    $CwdArg = $MatchRules.Groups['cwd'].Value
    $RestArgs = $MatchRules.Groups['restArgs'].Value
    $SlimRules = "function $FnRules($CwdArg$RestArgs){return``====\n\nRULES\n\n- Workspace Root: `${$CwdArg.toPosix()}. All file paths must be relative to `${$CwdArg.toPosix()} (never use ~ or `$HOME).\n- PowerShell 7 CLI: Chain commands with ; (not &&). Use native PowerShell cmdlets (Select-String, Get-Content, Remove-Item, Copy-Item, Move-Item, -replace) instead of Unix utilities (grep, cat, rm, cp, mv, sed, awk). For file I/O in PowerShell, always use UTF-8 No-BOM ([System.IO.File]::ReadAllText/WriteAllText with UTF8Encoding(`$false)) -- never bare Get-Content/Set-Content. Check Actively Running Terminals in environment_details before spawning processes.\n- Context Efficiency: Do not re-read files already provided in the prompt. Respect mode fileRegex restrictions.\n- Direct Execution: Never start messages with `"Great`", `"Certainly`", `"Okay`", or `"Sure`". Never end attempt_completion with a question or offer for further assistance.``}"
    $RawJs = [regex]::Replace($RawJs, $PatternRules, $SlimRules)
    Write-Host "  [+] Compressed RULES section ($FnRules) while preserving adjacent execa module" -ForegroundColor Green
} else {
    Write-Warning "  [!] Pattern not matched: RULES"
}

# Patch F: Expand built-in Architect mode's fileRegex from \.md$ to allow .txt and .*ignore
if (-not $SkipArchitectRegex) {
    if ($RawJs.Contains('fileRegex:"\\.md$"')) {
        $RawJs = $RawJs.Replace('fileRegex:"\\.md$"', 'fileRegex:"(\\.(md|txt)|^\\.[a-z0-9]+ignore)$"')
        Write-Host "  [+] Expanded built-in Architect fileRegex to allow .txt and .*ignore" -ForegroundColor Green
    } else {
        Write-Warning "  [!] Built-in Architect fileRegex (\\.md$) not found or already modified"
    }
}

[System.IO.File]::WriteAllText($ExtensionPath, $RawJs, $Utf8NoBom)
$BytesDiff = $RawJs.Length - $OriginalLength
Write-Host ("`n[SUCCESS] Patched dist/extension.js (Size delta: {0} bytes; ~1,560 prompt tokens saved per turn)." -f $BytesDiff) -ForegroundColor Cyan
Write-Host "Reload VS Code (Ctrl+Shift+P -> 'Developer: Reload Window') to apply." -ForegroundColor Yellow
