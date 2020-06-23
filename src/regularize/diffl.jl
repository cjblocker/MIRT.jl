#=
diffl.jl
left finite differences, in-place!

Inspired by:
https://docs.julialang.org/en/latest/manual/performance-tips/#Pre-allocating-outputs-1

2019-06-22 Jeff Fessler, University of Michigan
=#

export diffl, diffl!, diffl_adj, diffl_adj!, diffl_map

using LinearMapsAA: LinearMapAA
using Test: @test, @testset, @test_throws, @inferred


"""
    diffl!(g::AbstractArray, x::AbstractArray, dim::Int ; ...)

Left finite difference operator on an input array `x`,
storing the result "in-place" in output array `g`.
Arrays `g` and `x` must have the same size.
The "first" elements of `g` are zero for dimension `dim`.
The default is `dim=1`.

Option:
- `add::Bool = false` use `x[i] + x[i-1]` instead of `x[i] - x[i-1]`
- `edge::Symbol = :zero` set the first elements of dimension `dim` to 0

Choose `edge=:circ` to use circulant (aka periodic) boundary conditions.
Choose `edge=:none` to leave the first elements untouched.

The arrays `g` and `x` must be the same size.

In 1D, if `x = [2, 6, 7]` then `g = [0, 4, 1]`.
"""
function diffl!(g::AbstractArray{Tg,N}, x::AbstractArray{Tx,N}, dim::Int
	; edge::Symbol=:zero, add::Bool=false) where {Tg,Tx,N}

    Base.require_one_based_indexing(g) && Base.require_one_based_indexing(x)
    1 <= dim <= N || throw(ArgumentError("dimension $dim out of range (1:$N)"))
    size(g) != size(x) && throw(DimensionMismatch("sizes g=>$(size(g)) vs x=>$(size(x))"))

	Nd = size(x, dim)
	if add
		selectdim(g, dim, 2:Nd) .=
		selectdim(x, dim, 2:Nd) .+ selectdim(x, dim, 1:(Nd-1))
	else
		selectdim(g, dim, 2:Nd) .=
		selectdim(x, dim, 2:Nd) .- selectdim(x, dim, 1:(Nd-1))
	end

	# handle edge conditions
	g1 = selectdim(g, dim, 1)
	if edge === :zero
		g1 .= zero(Tg)
	elseif edge === :circ
		if add
			g1 .= selectdim(x, dim, 1) .+ selectdim(x, dim, Nd)
		else
			g1 .= selectdim(x, dim, 1) .- selectdim(x, dim, Nd)
		end
	else
		edge != :none && throw(ArgumentError("edge $edge"))
		# caution: in this case g1 is untouched, possibly undef
	end

	return g
end


# for default dim=1 case
diffl!(g::AbstractArray, x::AbstractArray ; kwargs...) = diffl!(g, x, 1 ; kwargs...)


"""
    diffl!(g::AbstractArray, x::AbstractArray, dims::AbstractVector{Int} ; ...)

When `x` is a `N`-dimensional array, the `i`th slice of the `g` array
(along its last dimension) is the `diffl!` of `x` along `dims[i]`.
This is useful for total variation (TV) and other regularizers
that need finite differences along multiple dimensions.
"""
function diffl!(g::AbstractArray{Tg,Ng}, x::AbstractArray{Tx,Nx},
		dims::AbstractVector{Int} ; kwargs...) where {Tg,Tx,Ng,Nx}

	Ng != Nx+1 && throw(DimensionMismatch("Ng=$Ng Nx=$Nx"))
    size(g) != (size(x)..., length(dims)) &&
		throw(DimensionMismatch("sizes g=>$(size(g)) vs x=>$(size(x))"))

	for (i,d) in enumerate(dims)
		diffl!(selectdim(g, Ng, i), x, d ; kwargs...)
	end
	return g
end


"""
    g = diffl(x::AbstractArray ; ...)
Allocating version of `diffl!` along `dim=1`
"""
diffl(x::AbstractArray ; kwargs...) = diffl(x, 1 ; kwargs...)

"""
    g = diffl(x::AbstractArray, dim::Int ; ...)
Allocating version of `diffl!` along `dim`
"""
diffl(x::AbstractArray, dim::Int ; kwargs...) = diffl!(similar(x), x, dim ; kwargs...)

"""
    g = diffl(x::AbstractArray, dims::AbstractVector{Int} ; ...)
Allocating version of `diffl!` for `dims`
"""
diffl(x::AbstractArray, dims::AbstractVector{Int} ; kwargs...) =
	diffl!(similar(x, size(x)..., length(dims)), x, dims ; kwargs...)


"""
    diffl(:test)
self test for `diffl` and `diffl!`
"""
function diffl(test::Symbol)
    test != :test && throw(ArgumentError("test $test"))

	@testset "1D" begin
		x = rand(4)
		@test diffl(x)[2:end] == diff(x)
	end

	@testset "2D" begin
    	x = [2 4; 6 16]
		g = @inferred diffl(x, 1)
		@test all(g[1,:] .== 0)
		@test g[2:end,:] == diff(x, dims=1)
		g = @inferred diffl(x, 2)
		@test all(g[:,1] .== 0)
		@test g[:,2:end] == diff(x, dims=2)

		g = @inferred diffl(x, 1 ; edge=:none)
		@test g[2:end,:] == diff(x, dims=1)

		g = @inferred diffl(x, 1 ; add=true)
		@test g[2:end,:][:] == x[1,:] + x[2,:]

		x = rand(3,4)
		g1 = diffl(x)
		g2 = similar(g1)
		@inferred diffl!(g2, x) # test default 1
		@test g2[2:end,:] == g1[2:end,:]
	end

	@testset "stack" begin
    	x = reshape((1:(2*3*4)).^2, 2, 3, 4)
		g = diffl(x, [3, 1])
		@test all(g[:,:,1,1] .== 0)
		@test all(g[1,:,:,2] .== 0)
		@test g[:,:,2:end,1] == diff(x, dims=3)
		@test g[2:end,:,:,2] == diff(x, dims=1)
	end

	@testset "adj" begin
		x = rand(3)
		@inferred diffl_adj(rand(3))
		@test_throws ArgumentError diffl_adj(rand(3) ; edge=:test)
	#	@inferred diffl_adj(rand(3,4,2), 1:2) # fails
		@test size(diffl_adj(rand(3,4,2), 1:2)) == (3,4)
	end

	true
end


"""
    diffl_adj!(z, g, dim::Int ; ...)

Adjoint of left finite difference `diffl!`, in-place.
Arrays `z` and `g` must be same size.
See `diffl` for details.
"""
function diffl_adj!(z::AbstractArray{Tz,N}, g::AbstractArray{Tg,N}, dim::Int
	; reset0::Bool=true,
	edge::Symbol=:zero, add::Bool=false,
) where {Tz,Tg,N}

    1 <= dim <= N || throw(ArgumentError("dimension $dim out of range (1:$N)"))
    size(z) != size(g) && throw(DimensionMismatch("sizes z=>$(size(z)) vs g=>$(size(g))"))

	# todo: handle reset0 better
	if reset0
		z .= zero(Tz)
	end

	Nd = size(g, dim)

	if edge === :zero
    	selectdim(z, dim, 2:Nd) .+= selectdim(g, dim, 2:Nd)
	elseif edge === :circ
    #	selectdim(z, dim, 1:Nd) .+= selectdim(g, dim, 1:Nd)
    	z .+= g
	else
		edge != :none && throw(ArgumentError("edge $edge"))
		# in this case g1 is unused, even if undef
	end

	if add
    	selectdim(z, dim, 1:(Nd-1)) .+= selectdim(g, dim, 2:Nd)
		if edge === :circ
    		selectdim(z, dim, Nd) .+= selectdim(g, dim, 1)
		end
	else
    	selectdim(z, dim, 1:(Nd-1)) .-= selectdim(g, dim, 2:Nd)
		if edge === :circ
    		selectdim(z, dim, Nd) .-= selectdim(g, dim, 1)
		end
	end

    return z
end


"""
    diffl_adj!(z::AbstractArray, g::AbstractArray, dims::AbstractVector{Int} ; ...)

Adjoint of `diffl!` for multiple dimensions `dims`.
Here `g` must have one more dimension than `z`.
"""
function diffl_adj!(z::AbstractArray{Tz,Nz}, g::AbstractArray{Tg,Ng},
		dims::AbstractVector{Int} ; kwargs...) where {Tz,Tg,Nz,Ng}

	Ng != Nz+1 && throw(DimensionMismatch("Ng=$Ng Nz=$Nz"))
    size(g) != (size(z)..., length(dims)) &&
		throw(DimensionMismatch("sizes g=>$(size(g)) vs z=>$(size(z))"))

	for (i,d) in enumerate(dims)
		diffl_adj!(z, selectdim(g, Ng, i), d ; reset0 = (i==1), kwargs...)
	end
	return z
end


"""
    z = diffl_adj(g::AbstractArray ; ...)
Allocating version of `diffl!` along `dim=1`
"""
diffl_adj(g::AbstractArray ; kwargs...) = diffl_adj(g, 1 ; kwargs...)

"""
    z = diffl(g::AbstractArray, dim::Int ; ...)
Allocating version of `diffl!` along `dim`
"""
diffl_adj(g::AbstractArray, dim::Int ; kwargs...) =
	diffl_adj!(similar(g), g, dim ; reset0=true, kwargs...)

"""
    z = diffl_adj(g::AbstractArray, dims::AbstractVector{Int} ; ...)
Allocating version of `diffl!` for `dims`
"""
function diffl_adj(g::AbstractArray{T,N}, dims::AbstractVector{Int}
	; kwargs...) where {T,N}
	size(g)[end] != length(dims) &&
		throw(DimensionMismatch("sizes g=>$(size(g)) vs dims=$dims"))
	diffl_adj!(similar(g, size(g)[1:(N-1)]...), g, dims ; kwargs...)
end


"""
    T = diffl_map(N::Dims{D}, dims::AbstractVector{Int} ; kwargs...)
    T = diffl_map(N::Dims{D}, dim::Int ; kwargs...)

in
- `N::Dims` image size

options: see `diffl!`
- `T::Type` for `LinearMapAA`, default `Float32`

out
- `T` `LinearMapAA` object for computing finite differences via `T*x`
using `diffl!` and `diffl_adj!`
"""
function diffl_map(N::Dims{D},
	dims::AbstractVector{Int} ;
	T::Type=Float32,
	edge::Symbol = :zero,
	kwargs...,
) where {D}

	!all(1 .<= dims .<= D) && throw(ArgumentError("dims $dims"))
	(edge == :none) && throw("edge=$edge unsupported")

	gshape = g -> reshape(g, N..., length(dims))
    return LinearMapAA(
        (g,x) -> diffl!(gshape(g), reshape(x, N), dims ; edge=edge, kwargs...),
        (z,g) -> vec(diffl_adj!(reshape(z,N), gshape(g), dims ; edge=edge, kwargs...)),
        (length(dims), 1) .* prod(N),
        (name="diffl_map", N=N, dims=dims),
		T=T,
    )
end

# todo: generalize LMAA for arrays to avoid reshape!

# for single dimension case
function diffl_map(N::Dims{D},
	dim::Int ;
	T::Type = Float32,
	edge::Symbol = :zero,
	kwargs...,
) where {D}

	(1 .<= dim .<= D) || throw(ArgumentError("dim $dim"))
	(edge == :none) && throw("edge=$edge unsupported")
	
    return LinearMapAA(
        (g,x) -> diffl!(reshape(g, N), reshape(x, N), dim ; edge=edge, kwargs...),
        (z,g) -> vec(diffl_adj!(reshape(z,N), reshape(g, N), dim ; edge=edge, kwargs...)),
        (1, 1) .* prod(N),
        (name="diffl_map", N=N, dim=dim),
		T=T,
    )
end

# default dim=1
diffl_map(N::Dims ; kwargs...) = diffl_map(N, 1, ; kwargs...)


"""
    diffl_map(:test)
self test
"""
function diffl_map(test::Symbol)
    test != :test && throw(ArgumentError("test $test"))

	N = (2,3); d = 2
    T = diffl_map(N, d ; T=Int32, edge=:zero, add=false)
    @test Matrix(T)' == Matrix(T')
    @test T.name == "diffl_map"

    @test_throws String diffl_map(N ; edge=:none) # unsupported

    for N in [(3,), (3,4), (2,3,4)]
		dlist = [1, [1,]]
		length(N) > 1 && push!(dlist, 2:-1:1, 1:length(N))
		length(N) > 2 && push!(dlist, [length(N), 1])
		isinteractive() && @show dlist
		for d in dlist
		#	@show d
			for edge in (:zero, :circ)
				for add in (false, true)
        			T = diffl_map(N, d ; T=Int32, edge=edge, add=add)
        			@test Matrix(T)' == Matrix(T')
            	end
            end
        end
    end

    true
end