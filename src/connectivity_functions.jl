"""
    connect_mesh(EToV,fv)

Initialize element connectivity matrices, element to element and element to face
connectivity.

Inputs:
- `EToV` is a `K` by `Nv` matrix whose rows identify the `Nv` vertices
which make up an element.
- `fv` (an array of arrays containing unordered indices of face vertices).

Output: `FToF`, `length(fv)` by `K` index array containing face-to-face connectivity.
"""
function connect_mesh(EToV,fv)
    Nfaces = length(fv)
    K = size(EToV,1)

    # sort and find matches
    fnodes = [[sort(EToV[e,ids]) for ids = fv, e = 1:K]...]
    p = sortperm(fnodes) # sorts by lexicographic ordering by default
    fnodes = fnodes[p,:]

    FToF = reshape(collect(1:Nfaces*K),Nfaces,K)
    for f = 1:size(fnodes,1)-1
        if fnodes[f,:]==fnodes[f+1,:]
            f1 = FToF[p[f]]
            f2 = FToF[p[f+1]]
            FToF[p[f]] = f2
            FToF[p[f+1]] = f1
        end
    end
    return FToF
end


"""
    build_node_maps(Xf,FToF)

Intialize the connectivity table along all edges and boundary node tables of all
elements. mapM - map minus (interior). mapP - map plus (exterior).

Xf = (xf,yf,zf) and FToF is size (Nfaces*K) and FToF[face] = face neighbor

mapM,mapP are size Nfp x (Nfaces*K)

# Examples
```julia
julia> mapM,mapP,mapB = build_node_maps((xf,yf),FToF)
```
"""

function build_node_maps(FToF,Xf...)

    NfacesK = length(FToF)
    NODETOL = 1e-10;
    dims = length(Xf)

    # number nodes consecutively
    Nfp  = convert(Int,length(Xf[1]) / NfacesK)
    mapM = reshape(collect(1:length(Xf[1])), Nfp, NfacesK);
    mapP = copy(mapM);

    ids = collect(1:Nfp)
    for (f1,f2) in enumerate(FToF)

        # find find volume node numbers of left and right nodes
        D = zeros(Nfp,Nfp)
        for i = 1:dims
            Xfi = reshape(Xf[i],Nfp,NfacesK)
            X1i = repeat(Xfi[ids,f1],1,Nfp)
            X2i = repeat(Xfi[ids,f2],1,Nfp)
            # Compute distance matrix
            D += abs.(X1i - transpose(X2i))
        end

        refd = maximum(D[:])
        idM = map(id->id[1], findall(@. D < NODETOL*refd))
        idP = map(id->id[2], findall(@. D < NODETOL*refd))
        mapP[idM,f1] = @. idP + (f2-1)*Nfp
    end

    mapB = map(x->x[1],findall(@. mapM[:]==mapP[:]))
    return mapM,mapP,mapB
end

"""
    make_periodic(md::MeshData{Dim},rd::RefElemData,is_periodic...) where {Dim}
    make_periodic(md::MeshData{Dim},rd::RefElemData,is_periodic=ntuple(x->true,Dim)) where {Dim}
    make_periodic(md::MeshData{1},rd::RefElemData,is_periodic=true)

Returns new MeshData such that the node maps `mapP` and face maps `FToF` are now periodic.
Here, `is_periodic` is a tuple of `Bool` indicating whether or not to impose periodic
BCs in the `x`,`y`, or `z` coordinate.
"""
make_periodic(md::MeshData,rd::RefElemData,is_periodic...) = make_periodic(md,rd,is_periodic)

function make_periodic(md::MeshData{Dim},rd::RefElemData,
                       is_periodic::NTuple{Dim,T}=ntuple(x->true,Dim)) where {Dim,T}
    @unpack mapM,mapP,mapB,xyzf,FToF = md
    NfacesTotal = prod(size(FToF))
    mapPB = build_periodic_boundary_maps!(xyzf...,is_periodic...,NfacesTotal,
                                          mapM, mapP, mapB, FToF)
    mapP[mapB] = mapPB
    return setproperties(md,(mapP=mapP,FToF=FToF)) # from Setfield.jl    
end

# specializes to 1D - periodic = find min/max indices of xf and reverse their order
function make_periodic(md::MeshData{1},rd::RefElemData,is_periodic=true)
    if is_periodic == true
        @unpack mapP,mapB,xf,FToF = md
        mapPB = argmax(vec(xf)),argmin(vec(xf))
        mapP[mapB] .= mapPB
        FToF[[1,length(FToF)]] .= mapPB
        return setproperties(md,(mapP=mapP,FToF=FToF)) # from Setfield.jl
    end
end

# Helper functions for `make_nodemaps_periodic!`, 2D version which modifies FToF.
function build_periodic_boundary_maps!(xf,yf,is_periodic_x, is_periodic_y,
                                       NfacesTotal,mapM,mapP,mapB,FToF)

        # find boundary faces (e.g., when FToF[f] = f)
        Flist = 1:length(FToF)
        Bfaces = findall(vec(FToF) .== Flist)

        xb = xf[mapB]
        yb = yf[mapB]
        Nfp = convert(Int,length(xf)/NfacesTotal)
        Nbfaces = convert(Int,length(xb)/Nfp)
        xb = reshape(xb,Nfp,Nbfaces)
        yb = reshape(yb,Nfp,Nbfaces)

        # compute centroids of faces
        xc = vec(sum(xb,dims=1)/Nfp)
        yc = vec(sum(yb,dims=1)/Nfp)
        mapMB = reshape(mapM[mapB],Nfp,Nbfaces)
        mapPB = reshape(mapP[mapB],Nfp,Nbfaces)

        xmin,xmax = extrema(xc)
        ymin,ymax = extrema(yc)

        NODETOL = 1e-12
        LX,LY = map((x->x[2]-x[1])∘extrema,(xf,yf))
        if abs(abs(xmax-xmin)-LX)>NODETOL && is_periodic_x
            error("periodicity requested in x, but max_dist(xf) != max_dist(xc)")
        end
        if abs(abs(ymax-ymin)-LY)>NODETOL && is_periodic_y
            error("periodicity requested in y, but max_dist(yf) != max_dist(yc)")
        end

        # determine which faces lie on x and y boundaries
        Xscale = max(1,LX)
        Yscale = max(1,LY)
        yfaces = map(x->x[1],findall(@. (@. abs(yc-ymax)<NODETOL*Yscale) | (@. abs(yc-ymin)<NODETOL*Yscale)))
        xfaces = map(x->x[1],findall(@. (@. abs(xc-xmax)<NODETOL*Xscale) | (@. abs(xc-xmin)<NODETOL*Xscale)))

        if is_periodic_y # find matches in y faces
            for i in yfaces, j in yfaces
                if i!=j
                    if abs(xc[i]-xc[j])<NODETOL*Xscale && abs(abs(yc[i]-yc[j])-LY)<NODETOL*Yscale
                        Xa,Xb = meshgrid(xb[:,i],xb[:,j])
                        D = @. abs(Xa-Xb)
                        ids = map(x->x[1],findall(@.D < NODETOL*Xscale))
                        mapPB[:,i]=mapMB[ids,j]

                        FToF[Bfaces[i]] = Bfaces[j]
                    end
                end
            end
        end

        if is_periodic_x # find matches in x faces
            for i in xfaces, j in xfaces
                if i!=j
                    if abs(yc[i]-yc[j])<NODETOL*Yscale && abs(abs(xc[i]-xc[j])-LX)<NODETOL*Xscale
                        Ya,Yb = meshgrid(yb[:,i],yb[:,j])
                        D = @. abs(Ya-Yb)
                        ids = map(x->x[1],findall(@. D < NODETOL*Yscale))
                        mapPB[:,i]=mapMB[ids,j]

                        FToF[Bfaces[i]] = Bfaces[j]
                    end
                end
            end
        end

        return mapPB[:]
end

# 3D version of build_periodic_boundary_maps, modifies FToF
function build_periodic_boundary_maps!(xf,yf,zf,
                                       is_periodic_x,is_periodic_y,is_periodic_z,
                                       NfacesTotal,mapM,mapP,mapB,FToF)

    # find boundary faces (e.g., when FToF[f] = f)
    Flist = 1:length(FToF)
    Bfaces = findall(vec(FToF) .== Flist)

    xb,yb,zb = xf[mapB],yf[mapB],zf[mapB]
    Nfp = convert(Int,length(xf)/NfacesTotal)
    Nbfaces = convert(Int,length(xb)/Nfp)
    xb,yb,zb = (x->reshape(x,Nfp,Nbfaces)).((xb,yb,zb))

    # compute centroids of faces
    xc = vec(sum(xb,dims=1)/Nfp)
    yc = vec(sum(yb,dims=1)/Nfp)
    zc = vec(sum(zb,dims=1)/Nfp)
    mapMB = reshape(mapM[mapB],Nfp,Nbfaces)
    mapPB = reshape(mapP[mapB],Nfp,Nbfaces)

    xmin,xmax = extrema(xc)
    ymin,ymax = extrema(yc)
    zmin,zmax = extrema(zc)

    NODETOL = 1e-12
    LX,LY,LZ = map((x->x[2]-x[1])∘extrema,(xf,yf,zf))
    if abs(abs(xmax-xmin)-LX)>NODETOL && is_periodic_x
        error("periodicity requested in x, but max_dist(xf) != max_dist(xc)")
    end
    if abs(abs(ymax-ymin)-LY)>NODETOL && is_periodic_y
        error("periodicity requested in y, but max_dist(yf) != max_dist(yc)")
    end
    if abs(abs(zmax-zmin)-LZ)>NODETOL && is_periodic_z
        error("periodicity requested in z, but max_dist(zf) != max_dist(zc)")
    end

    # determine which faces lie on x and y boundaries
    xfaces = map(x->x[1],findall(@. (@. abs(xc-xmax)<NODETOL*LX) | (@. abs(xc-xmin)<NODETOL*LX)))
    yfaces = map(x->x[1],findall(@. (@. abs(yc-ymax)<NODETOL*LY) | (@. abs(yc-ymin)<NODETOL*LY)))
    zfaces = map(x->x[1],findall(@. (@. abs(zc-zmax)<NODETOL*LZ) | (@. abs(zc-zmin)<NODETOL*LZ)))

    if is_periodic_x # find matches in x faces
        for i in xfaces, j in xfaces
            if i!=j
                if abs(yc[i]-yc[j])<NODETOL*LY && abs(zc[i]-zc[j])<NODETOL*LZ && abs(abs(xc[i]-xc[j])-LX)<NODETOL*LX
                    Ya,Yb = meshgrid(yb[:,i],yb[:,j])
                    Za,Zb = meshgrid(zb[:,i],zb[:,j])
                    D = @. abs(Ya-Yb) + abs(Za-Zb)
                    ids = map(x->x[1],findall(@.D < NODETOL*LY))
                    mapPB[:,i]=mapMB[ids,j]

                    FToF[Bfaces[i]] = Bfaces[j]
                end
            end
        end
    end

    # find matches in y faces
    if is_periodic_y
        for i in yfaces, j = yfaces
            if i!=j
                if abs(xc[i]-xc[j])<NODETOL*LX && abs(zc[i]-zc[j])<NODETOL*LZ && abs(abs(yc[i]-yc[j])-LY)<NODETOL*LY
                    Xa,Xb = meshgrid(xb[:,i],xb[:,j])
                    Za,Zb = meshgrid(zb[:,i],zb[:,j])
                    D = @. abs(Xa-Xb) + abs(Za-Zb)
                    ids = map(x->x[1],findall(@.D < NODETOL*LX))
                    mapPB[:,i]=mapMB[ids,j]

                    FToF[Bfaces[i]] = Bfaces[j]
                end
            end
        end
    end

    # find matches in z faces
    if is_periodic_z
        for i in zfaces, j in zfaces
            if i!=j
                if abs(xc[i]-xc[j])<NODETOL*LX && abs(yc[i]-yc[j])<NODETOL*LY && abs(abs(zc[i]-zc[j])-LZ)<NODETOL*LZ
                    Xa,Xb = meshgrid(xb[:,i],xb[:,j])
                    Ya,Yb = meshgrid(yb[:,i],yb[:,j])
                    D = @. abs(Xa-Xb) + abs(Ya-Yb)
                    ids = map(x->x[1],findall(@.D < NODETOL*LX))
                    mapPB[:,i]=mapMB[ids,j]

                    FToF[Bfaces[i]] = Bfaces[j]
                end
            end
        end
    end

    return mapPB[:]
end