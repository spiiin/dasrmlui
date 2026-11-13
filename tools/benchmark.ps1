param(
    [int[]]$Rows = @(100, 1000),
    [ValidateRange(1, 100000)][int]$Samples = 120,
    [ValidateRange(1, 100000)][int]$Warmup = 30,
    [ValidateRange(1, 100)][int]$Rounds = 4,
    [string]$BuildDir = 'build'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = if ([IO.Path]::IsPathRooted($BuildDir)) { $BuildDir } else { Join-Path $root $BuildDir }
$keys = @('SDL_VIDEODRIVER', 'RUI_BENCH_ROWS', 'RUI_BENCH_SAMPLES', 'RUI_BENCH_WARMUP', 'RUI_BENCH_ROUNDS')
$saved = @{}
foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
Push-Location $root
try {
    New-Item -ItemType Directory -Force logs | Out-Null
    & cmake -S . -B $build -DDASRMLUI_BUILD_BENCHMARKS=ON
    if ($LASTEXITCODE) { throw 'Configure failed' }
    & "$PSScriptRoot/build.ps1" -BuildDir $build
    if ($LASTEXITCODE) { throw 'Build failed' }
    $env:SDL_VIDEODRIVER = 'windows'
    $env:RUI_BENCH_SAMPLES = "$Samples"
    $env:RUI_BENCH_WARMUP = "$Warmup"
    $env:RUI_BENCH_ROUNDS = "$Rounds"
    $metadata = [ordered]@{
        date = (Get-Date).ToString('o')
        cpu = (Get-ItemPropertyValue 'HKLM:/HARDWARE/DESCRIPTION/System/CentralProcessor/0' ProcessorNameString)
        os = [Environment]::OSVersion.VersionString
        rows = $Rows; samples = $Samples; warmup = $Warmup; timing_rounds = $Rounds
        build = $build
        compiler_and_flags = @(Get-Content "$build/CMakeCache.txt" | Select-String '^(CMAKE_BUILD_TYPE|CMAKE_CXX_COMPILER|CMAKE_CXX_FLAGS_RELEASE):' | ForEach-Object { $_.Line })
    }
    $metadata | ConvertTo-Json | Set-Content logs/binding-benchmark-environment.json
    foreach ($size in $Rows) {
        if ($size -lt 2 -or $size -gt 100000) { throw 'Rows must be between 2 and 100000' }
        $env:RUI_BENCH_ROWS = "$size"
        & "$build/bin/dasrmlui_bench.exe" benchmarks/bindings.das 2>&1 |
            Tee-Object "logs/binding-benchmark-$size.log"
        if ($LASTEXITCODE) { throw "Benchmark failed for $size rows" }
        & python benchmarks/analyze.py "logs/binding-benchmark-$size.csv"
        if ($LASTEXITCODE) { throw 'Analysis failed' }
    }
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    Pop-Location
}
