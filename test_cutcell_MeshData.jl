using NodesAndModes: face_basis
using Plots
using LinearAlgebra
using StaticArrays
using StartUpDG
using PathIntersections

N = 3
quad_rule_face = gauss_lobatto_quad(0, 0, N)
rd = RefElemData(Quad(), N; quad_rule_face)

cells_per_dimension = 4
circle = PresetGeometries.Circle(R=0.66, x0=0, y0=0)
objects = (circle, )

# TODO: remove eventually
cells_per_dimension_x = cells_per_dimension
cells_per_dimension_y = cells_per_dimension
vx = LinRange(-1, 1, cells_per_dimension_x + 1)
vy = LinRange(-1, 1, cells_per_dimension_y + 1)    

#######################################
#        test weak SBP property       #
#######################################

md = StartUpDG.MeshData2(rd, objects, vx, vy; precompute_operators=true)
mt = md.mesh_type

for (e, elem) in enumerate(mt.physical_frame_elements)
    xq, yq, wq = md.xq.cut[:,e], md.yq.cut[:,e], md.wJq.cut[:,e]

    Vq, Vxq, Vyq = basis(elem, rd.N, xq, yq)
    face_ids = mt.cut_face_nodes[e]
    Vf = vandermonde(elem, rd.N, md.xf.cut[face_ids], md.yf.cut[face_ids]) 
    Qx, Qy = Vq' * diagm(wq) * Vxq, Vq' * diagm(wq) * Vyq

    (; wJf) = md.mesh_type.cut_cell_data
    Bx = Diagonal(wJf.cut[face_ids] .* md.nxJ.cut[face_ids])
    By = Diagonal(wJf.cut[face_ids] .* md.nyJ.cut[face_ids])

    # represent constant vector in basis
    ee = Vq \ ones(size(Vq, 1))
    @show norm(ee' * Qx - ee' * Vf' * Bx * Vf)
    @show norm(ee' * Qy - ee' * Vf' * By * Vf)
end

# plot pruned cells

# volume quadrature should be exact for degree N(N-1) + 2N-2 polynomials, 
# or N(N-1) + 2(N-1) = (N+2) * (N-1) degrees
N_phys_frame_geo = max(2 * N, (N-1) * (N + 2))     
target_degree = 2 * N
rd_tri = RefElemData(Tri(), Polynomial(MultidimensionalQuadrature()), N, 
                    quad_rule_vol=NodesAndModes.quad_nodes_tri(N_phys_frame_geo))
Np_target = StartUpDG.Np_cut(target_degree)

plot()
for e in eachindex(cutcells)
    xq, yq, _ = StartUpDG.subtriangulated_cutcell_quadrature(cutcells[e], rd_tri)
    scatter!(vec(xq), vec(yq), label="Reference quadrature"); 
    scatter!(xq_pruned[:,e], yq_pruned[:,e], markersize=8, marker=:circle, 
             z_order=:back, label="Caratheodory pruning", leg=false)
end
display(plot!(leg=false))
