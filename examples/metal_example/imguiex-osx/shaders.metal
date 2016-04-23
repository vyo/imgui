
#include <metal_stdlib>
using namespace metal;

struct vertex_t {
    float2 position [[attribute(0)]];
    float2 tex_coords [[attribute(1)]];
    uchar4 color [[attribute(2)]];
};

struct frag_data_t {
    float4 position [[position]];
    float4 color;
    float2 tex_coords;
};

vertex frag_data_t vertex_function(vertex_t vertex_in [[stage_in]],
                                   constant float4x4 &proj_matrix [[buffer(1)]])
{
    float2 position = vertex_in.position;

    frag_data_t out;
    out.position = proj_matrix * float4(position.xy, 0, 1);
    out.color = float4(vertex_in.color) * (1 / 255.0);
    out.tex_coords = vertex_in.tex_coords;
    return out;
}

fragment float4 fragment_function(frag_data_t frag_in [[stage_in]],
                                  texture2d<float, access::sample> tex [[texture(0)]],
                                  sampler tex_sampler [[sampler(0)]])
{
    return frag_in.color * float4(tex.sample(tex_sampler, frag_in.tex_coords).r);
}
