# Build21 loader failure

Resolver works including sibling dSYM. BUNDLE/host/provider/product/test compile/sign/open pass, then missing libXCTestSwiftSupport.dylib prevents Bundle.load. No tests start; input NOT_RUN and no product acceptance/finding/promotion. Carrier58d15b69, production6934c unchanged. Total187.59s. Earlier evidence retained; released0dcd982 unchanged.
