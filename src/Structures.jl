export load_structure_from_ply, transform, transform!

"""
    load_structure_from_ply(filename)

Load a .ply file into a mesh

Uses MeshIO to load the mesh from the file. Unfortunately, MeshIO loads into
GeometryBasics.Mesh, not Meshes.SimpleMesh. The rest of the code converts the
mesh into a Meshes.SimpleMesh.
From https://github.com/JuliaIO/MeshIO.jl/issues/67#issuecomment-913353708
"""
function load_structure_from_ply(filename)
	mesh = FileIO.load(filename)
	points = [Float64.(Tuple(p)) for p in Set(mesh.position)]
	indices = Dict(p => i for (i, p) in enumerate(points))
	connectivities = map(mesh) do el
		Meshes.connect(Tuple(indices[Tuple(p)] for p in el))
	end
	Meshes.SimpleMesh(points, connectivities)
end

#--- Mesh Transformations -----------------------------------------------------
"""
    transform(mesh::SimpleMesh, trans)

Apply general transformation `trans` to `mesh``.
"""
function transform(mesh::SimpleMesh, trans)
    points = Point.(trans.(coordinates.(vertices(mesh))))
    SimpleMesh(points, topology(mesh))
end

"""
    transform!(mesh::SimpleMesh, trans)

Apply general transformation `trans` to `mesh`, modifying the original mesh.
"""
function transform!(mesh, trans)
    mesh.points .= Point.(trans.(coordinates.(vertices(mesh)))) 
end

#--- Mesh Intersection --------------------------------------------------------

"""
    intersect_mesh(s, mesh)

Find the intersection points of the `line` and the `mesh`.

Returns a list of intersection points, and an empty list if none present.
"""
function intersect_mesh(line::Segment, mesh::Domain{Dim, T}) where {Dim, T}
    pI = Point{Dim, T}[]
    for cell in mesh
        pt = intersect(line, cell)
        if(pt !== nothing)
            push!(pI, pt)
        end
    end
    pI
end

"""
    intersect_mesh(line::Segment, mesh::Partition[, boxes])

Intersect a partitioned mesh.

Will check intersection with the bounding box of each partition before checking 
for intersection between each cell. Can pre-compute bounding boxes for extra
performance. Single threaded.
"""
function intersect_mesh(line::Segment{Dim, T}, mesh::Partition{<:Domain{Dim, T}},
    boxes) where {Dim, T}
    pI = Point{Dim, T}[]
    ray = Ray(line(0.), line(1.)-line(0.))
    for (i, block) in enumerate(mesh)
        intersection(ray, boxes[i]) do I
            if type(I) != NotIntersecting
                append!(pI, intersect_mesh(line, block))
            end
        end
    end
    pI
end
intersect_mesh(line::Segment, mesh::Partition{<:Domain}) = intersect_mesh(line, mesh, boundingbox.(mesh))

#--- Closest Intersection ------------------------------------------------------

"""
    closest_intersection(p1, p2, mesh::Domain)

Return the point on the line `p1->p2` and `mesh` closest to `p1`

Finds all points of intersection, then returns the point closest to `p1`.
If no intersections are found, it returns `nothing`.
"""
function closest_intersection(p1, p2, mesh, args...)
    # Find intersection points
    segment = Segment(Point(p1), Point(p2))
    pI = intersect_mesh(segment, mesh, args...)

    # If none found, return nothing
    length(pI)==0 && return nothing

    # Otherwise, return the closest
    length(pI)==1 && return coordinates(pI[1])

    s = argmin(@. norm(coordinates(pI)-(p1,)))
    coordinates(pI[s])
end

#--- File IO ------------------------------------------------------------------

"""
    write_vtk(filename, mesh::SimpleMesh)

Save a `SimpleMesh` to a VTK (.vtu) file.
"""
function write_vtk(filename, mesh::SimpleMesh)
    id = [indices(e) for e in elements(topology(mesh))]
    vtkfile = vtk_grid(filename,
                       coordinates.(vertices(mesh)), 
                       MeshCell.(Ref(VTKCellTypes.VTK_TRIANGLE), id))
    vtk_save(vtkfile)
end


function isinside(testpoint::Point{3,T}, mesh::Mesh{3,T}) where T
    if !(eltype(mesh) <: Triangle)
      error("This function only works for surface meshes with triangles as elements.")
    end
    ex = testpoint .- extrema(mesh)
    direction = ex[argmax(norm.(ex))]
    r = Ray(testpoint, direction*2)
    
    intersects = false
    for elem in mesh
      if intersection(x -> x.type == NoIntersection ? false : true, r, elem)
        intersects = !intersects
      end
    end
    intersects
end
