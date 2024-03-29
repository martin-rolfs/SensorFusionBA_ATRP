# This file contains functionality to realize the UKF in code.

#= 
Use as State: 
    x = [p_x, p_y, p_z, Ψ, Θ]
The Roll angle is not used here as it is not relevant for position change

Use as Input:
    u = [w_x, w_y, w_z, v, dt, steerAngle]
=#

"""
This function updates the state according to definitions on top of the file.
# Arguments 
- `s::Vector{Float32}`: The last state of the system. 
- `u::Vector{Float32}`: The input to update the estimation.

# Returns 
- `Vector{Float32}`: The resulting updated state vector. 
"""
function f(s::Vector{Float32}, u::Vector{Float32})
    Ψₜ = Ψ(s[4], u[5], u[6], β(u[6]), u[4])
    θₜ = θ_ang(s[5], u[5], [u[1], u[2], u[3]])
    ṡ = changeInPosition([u[1], u[2], u[3]], u[4], Ψₜ, θₜ, u[5], β=β(u[6]))
    p = s[1:3] + u[5]*ṡ

    return [p[1], p[2], p[3], Ψₜ, θₜ]
end

"""
This performs the whole prediction step for the UKF.

# Arguments
- `μₜ₋₁::Vector{Float32}`: The previous mean e.g. state.
- `wₘ::Vector{Float32}`: The weights for the mean.
- `wₖ::Vector{Float32}`: The weights for the covariance.
- `Χₜ₋₁::Vector{Vector{Float32}}`: The previous Sigma points.
- `uₜ::Vector{Float32}`: The input for the system.
- `Σₜ₋₁::Matrix{Float32}`: The covariance of previous estimation.
- `p::PredictionSettings`: Parameters to influence estimation.

# Returns
- `μₜ̇`: Predicted state.
- `Χₜ`: Next Sigma Points.
- `Σₜ`: New covariance.
"""
function UKF_prediction(μₜ₋₁::Vector{Float32}, wₘ::Vector{Float32}, wₖ::Vector{Float32}, Χₜ₋₁::Vector{Vector{Float32}}, uₜ::Vector{Float32}, Σₜ₋₁::Matrix{Float32}, p::PredictionSettings)
    # Compute F matrix
    F = Matrix{Float32}(undef, n, 0)
    for i ∈ 0:2*n  F = hcat(F, f(Χₜ₋₁[i+1], uₜ)) end

    # mean of the state
    μₜ̇ = sum(wₘ[i+1]*F[:, i+1] for i ∈ 0:2*n)

    # generate new sigma points
    Χₜ = generateSigmaPoints(μₜ₋₁, Σₜ₋₁, p)

    # compute covariance
    Σₜ = sum(wₖ[i+1]*(F[:, i+1] - μₜ̇)*transpose(F[:, i+1] - μₜ̇) for i ∈ 0:2*n) + p.processNoiseS*Matrix(I, size(Σₜ₋₁))
    #Σₜ[abs.(Σₜ) .< 10^-4] .= 0.0
    
    #Σₜ = round.(Σₜ, digits=4)
    #if !ishermitian(Σₜ) @warn "Sigma from Prediction not hermitian!" end

    return μₜ̇, Χₜ, Σₜ
end


"""
Update step of the unscented Kalman Filter.

# Returns
- `μₜ`: The new mean state.
- `Σₜ`: The new covariance.
"""
function UKF_update(μₜ̇::Vector{Float32}, wₘ::Vector{Float32}, wₖ::Vector{Float32}, Χₜ::Vector{Vector{Float32}}, Σₜ̇::Matrix{Float32}, p::PredictionSettings, measurement::Vector{Float32}, ratedCC::Float32)
    # Compute measurement matrix
    Zₜ = Matrix{Float32}(undef, n, 0)
    for i ∈ 1:2*n+1
        Zₜ = hcat(Zₜ, Χₜ[i])# normally: Hₛ*Χₜ[i]
    end

    # measurement mean
    zₜ = sum(wₘ[i+1]*Zₜ[:, i+1] for i ∈ 0:2*n)

    # Define helper matrix 
    Sₜ = sum(wₖ[i+1]*(Zₜ[:, i+1] - zₜ)*transpose(Zₜ[:, i+1] - zₜ) for i ∈ 0:2*n) + ((1-ratedCC)*p.measurementNoiseS)*Matrix(I, n, n)

    # calculate Kalman gain
    Kₜ = sum(wₖ[i+1]*(Χₜ[i+1] - μₜ̇)*transpose(Zₜ[:, i+1] - zₜ) for i ∈ 0:2*n) * inv(Sₜ)

    μₜ = μₜ̇ + Kₜ*(measurement - zₜ)
    Σₜ = Σₜ̇ - Kₜ*Sₜ*transpose(Kₜ)

    # Contrain the covariance matrix
    Σₜ[isnan.(Σₜ)] .= 0.0
    Σₜ[isinf.(Σₜ)] .= 1e10
    return μₜ, Σₜ
end

"""
Compute the weights for the unscented transform.

# Arguments
- `mean::Bool`: If true computes weights for mean, if not for covariance.
- `params::PredictionSettings`: Parameters to influence estimation.
# Returns 
- `Vector{Float32}`: The new weights.
"""
function computeWeights(mean::Bool, p::PredictionSettings)
    w = Vector{Float32}(undef, 0)
    λ = p.α^2*(n + p.κ) - n

    if mean push!(w, λ/(n+λ))
    else push!(w, λ/(n+λ) + (1-p.α^2+2)) end

    for i ∈ 1:2*n
        push!(w, 1/(2*(n+λ)))
    end 
    return w
end

"""
Generate Sigma points from previous mean and covariance.

# Arguments
- `μₜ::Vector{Float32}`: The previous state containing the position and θ, Ψ
- `Σₜ::Matrix{Float32}`: The covariance of previous estimation.
- `p::PredictionSettings`: Parameters to influence estimation.
# Returns
- `Vector{Vector{Float32}}`: The new sigma points.
"""
function generateSigmaPoints(μₜ₋₁::Vector{Float32}, Σₜ₋₁::Matrix{Float32}, p::PredictionSettings)
    # Define vector holding sigma points
    Χ = Vector{Vector{Float32}}(undef, 0)

    # Add the last mean
    push!(Χ, μₜ₋₁)

    λ = p.α^2*(n + p.κ) - n
    
    matrixRoot = real.(sqrt((n + λ) * Σₜ₋₁))
    # This is not easily done as alot of matrix operations lead to inaccuray
    # So receiving matrix is often not hermitian
    #matrixRoot = cholesky((n + λ) * forceHermetian(Σₜ₋₁)).U

    # Add the remaining sigma points spread around mean
    for i ∈ 1:n
        push!(Χ, μₜ₋₁ + matrixRoot[:, i])
    end

    for i ∈ 1:n
        push!(Χ, μₜ₋₁ - matrixRoot[:, i])
    end
    return Χ
end

"""
Helper function to force a matrix to be hermetian as due to floating point errors, this might not be the case.
"""
function forceHermetian(m::Matrix{Float32})
    s = size(m)
    for x ∈ 1:s[1]
        for y ∈ 1:s[2]
            if x == y 
                m[x,y] = abs(m[x,y])
                if m[x,y] == 0.0
                    m[x,y] = 0.001
                end

                continue 
            end

            #if m[x,y] == m[y,x] continue end

            m[x,y] = 0.0#m[y,x]
        end    
    end
    return m
end
