import TimeZones: DEPS_DIR
import Compat: unsafe_get

# https://github.com/JuliaLang/Compat.jl/pull/345
if VERSION < v"0.6.0-dev.2347"
    Base.isassigned(x::Base.RefValue) = isdefined(x, :x)
end

const LATEST_FILE = joinpath(DEPS_DIR, "latest")
const LATEST_FORMAT = Base.Dates.DateFormat("yyyy-mm-ddTHH:MM:SS")
const LATEST_DELAY = Hour(1)  # In 1996 a correction to a release was made an hour later

function read_latest(io::IO)
    version = readline(io)
    retrieved_utc = DateTime(readline(io), LATEST_FORMAT)
    return version, retrieved_utc
end

function read_latest(filename::AbstractString)
    open(filename, "r") do io
        read_latest(io)
    end
end

function write_latest(io::IO, version::AbstractString, retrieved_utc::DateTime)
    write(io, version)
    write(io, "\n")
    write(io, Dates.format(retrieved_utc, LATEST_FORMAT))
end

T = Tuple{AbstractString, DateTime}
const LATEST = isfile(LATEST_FILE) ? Ref{T}(read_latest(LATEST_FILE)) : Ref{T}()

function set_latest(version::AbstractString, retrieved_utc::DateTime)
    LATEST[] = version, retrieved_utc
    open(LATEST_FILE, "w") do io
        write_latest(io, version, retrieved_utc)
    end
end

function latest_version(now_utc::DateTime=now(Dates.UTC))
    if isassigned(LATEST)
        latest_version, latest_retrieved_utc = LATEST[]

        if now_utc - latest_retrieved_utc < LATEST_DELAY
            return Nullable{AbstractString}(latest_version)
        end
    end

    return Nullable{AbstractString}()
end

"""
    tzdata_url(version="latest") -> AbstractString

Generates a HTTPS URL for the specified tzdata version. Typical version strings are
formatted as 4-digit year followed by a lowercase ASCII letter. Available versions can be
are listed on "ftp://ftp.iana.org/tz/releases/" which start with "tzdata".

# Examples
```julia
julia> tzdata_url("2017a")
"https://www.iana.org/time-zones/repository/releases/tzdata2017a.tar.gz"
```
"""
function tzdata_url(version::AbstractString="latest")
    # Note: We could also support FTP but the IANA server is unreliable and likely
    # to break if working from behind a firewall.
    if version == "latest"
        "https://www.iana.org/time-zones/repository/tzdata-latest.tar.gz"
    else
        "https://www.iana.org/time-zones/repository/releases/tzdata$version.tar.gz"
    end
end

"""
    tzdata_download(version="latest", dir=tempdir()) -> AbstractString

Downloads a tzdata archive from IANA using the specified `version` to the specified
directory. See `tzdata_url` for details on tzdata version strings.
"""
function tzdata_download(version::AbstractString="latest", dir::AbstractString=tempdir())
    now_utc = now(Dates.UTC)
    if version == "latest"
        v = latest_version(now_utc)
        if !isnull(v)
            archive = joinpath(dir, "tzdata$(unsafe_get(v)).tar.gz")
            isfile(archive) && return archive
        end
    end

    url = tzdata_url(version)
    archive = Base.download(url, joinpath(dir, basename(url)))  # Overwrites the local file if any

    # Note: An "HTTP 404 Not Found" may result in the 404 page being downloaded. Also,
    # catches issues with corrupt archives
    if !isarchive(archive)
        rm(archive)
        error("Unable to download $version tzdata")
    end

    # Rename the file to have an explicit version
    if version == "latest"
        version = tzdata_version_archive(archive)

        archive_versioned = joinpath(dir, "tzdata$version.tar.gz")
        mv(archive, archive_versioned, remove_destination=true)
        archive = archive_versioned

        set_latest(version, now_utc)
    end

    return archive
end
