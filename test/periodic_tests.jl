using Base.Test, OrdinaryDiffEq, DiffEqCallbacks

tmin = 0.1
for tmax in [5.2; -5.2]
    for tmax_problem in [tmax; (tmax - tmin) * Inf]
        # Test with both a finite and an infinite tspan for the ODEProblem.
        #
        # Having support for infinite tspans is one of the main reasons for implementing PeriodicCallback
        # using add_tstop!, instead of just passing in a linspace as the tstops solve argument.
        # (the other being that the length of the internal tstops collection would otherwise become
        # linear in the length of the integration time interval.
        #
        # Testing a finite tspan is necessary because a naive implementation could add tstops after
        # tmax and thus integrate for too long (or even indefinitely).

        # Dynamics: two independent single integrators:
        du = [0; 0]
        u0 = [0.; 0.]
        dynamics = (t, u) -> eltype(u).(du)
        prob = ODEProblem(dynamics, u0, (tmin, tmax_problem))

        # Callbacks periodically increase the input to the integrators:
        dir = sign(tmax - tmin)
        Δt1 = dir * 0.5
        increase_du_1 = integrator -> du[1] += 1
        periodic1_initialized = Ref(false)
        initialize1 = (c, t, u, integrator) -> periodic1_initialized[] = true
        periodic1 = PeriodicCallback(increase_du_1, Δt1; initialize = initialize1)

        Δt2 = dir * 1.
        increase_du_2 = integrator -> du[2] += 1
        periodic2 = PeriodicCallback(increase_du_2, Δt2)

        # Terminate at tmax (regardless of whether the tspan of the ODE problem is infinite).
        terminator = DiscreteCallback((t, u, integrator) -> t == tmax, terminate!)

        # Solve.
        sol = solve(prob, Tsit5(); callback = CallbackSet(terminator, periodic1, periodic2), tstops = [tmax])

        # Ensure that initialize1 has been called
        @test periodic1_initialized[]

        # Make sure we haven't integrated past tmax:
        @test sol.t[end] == tmax

        # Make sure that the components of du have been incremented the appropriate number of times.
        Δts = [Δt1, Δt2]
        expected_num_calls = map(Δts) do Δt
            floor(Int, (tmax - tmin) / Δt) + 1
        end
        @test du == expected_num_calls

        # Make sure that the final state matches manual integration of the piecewise linear function
        foreach(Δts, sol.u[end], du) do Δt, u_i, du_i
            @test u_i ≈ Δt * sum(1 : du_i - 1) + rem(tmax - tmin, Δt) * du_i atol = 1e-5
        end
    end
end
