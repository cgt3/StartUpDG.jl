@testset "Geometric terms for $elem elements" for elem in [Tri() Quad() Hex()]
    tol = 5e2*eps()
    N = 3
    rd = RefElemData(elem,N)
    geofacs = geometric_factors(rd.rst...,rd.Drst...)
    if elem != Hex()
        rxJ,sxJ,ryJ,syJ,J = geofacs    
        @test all(rxJ .≈ 1)
        @test norm(sxJ) < tol
        @test norm(ryJ) < tol
        @test all(syJ .≈ 1)
        @test all(J .≈ 1)
    else
        rxJ, sxJ, txJ, ryJ, syJ, tyJ, rzJ, szJ, tzJ, J = geofacs
        @test all(rxJ .≈ 1)
        @test norm(sxJ) < tol
        @test norm(txJ) < tol
        @test norm(ryJ) < tol
        @test all(syJ .≈ 1)
        @test norm(tyJ) < tol
        @test norm(rzJ) < tol
        @test norm(szJ) < tol
        @test all(tzJ .≈ 1)
        @test all(J .≈ 1)
    end
end